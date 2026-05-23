//
//  BorderTrailRenderer.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//
//  The renderer drives a CAMetalLayer directly (not MTKView) via CAMetalDisplayLink,
//  which delivers the next drawable and target vsync timestamp to the delegate so
//  the render loop runs at the display refresh rate without blocking on
//  `nextDrawable()` acquire. Work happens on a private serial render queue.
//
//  Storage / API is unified by EffectType: every effect submits a mesh tagged
//  with its type; the renderer looks up the matching pipeline from a single
//  dict. Pipelines, draw order and the effect catalogue all come from
//  EffectRegistry.
//

import AppKit
import Metal
import OSLog
import QuartzCore
import simd

/// A single vertex submitted to the renderer. `edgeDist` is the
/// signed normalised distance from the geometry's centerline / center,
/// used by the fragment shaders for anti-aliasing and glow shaping.
struct EffectVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
    var alpha: Float
    var edgeDist: Float
}

/// Generic geometry container submitted to the renderer.
struct EffectMesh {
    var vertices: [EffectVertex]
    var primitiveType: MTLPrimitiveType = .triangleStrip
}

/// How an effect's pipeline blends into the framebuffer.
enum BlendMode {
    case additive
    case alphaBlend

    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true
        switch self {
        case .additive:
            attachment.rgbBlendOperation           = .add
            attachment.alphaBlendOperation         = .add
            attachment.sourceRGBBlendFactor        = .sourceAlpha
            attachment.destinationRGBBlendFactor   = .one
            attachment.sourceAlphaBlendFactor      = .sourceAlpha
            attachment.destinationAlphaBlendFactor = .one
        case .alphaBlend:
            attachment.rgbBlendOperation           = .add
            attachment.alphaBlendOperation         = .add
            attachment.sourceRGBBlendFactor        = .sourceAlpha
            attachment.destinationRGBBlendFactor   = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor      = .sourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
    }
}

/// Pipeline declaration provided by each effect descriptor. Pure data; the
/// renderer compiles the actual `MTLRenderPipelineState` from a `PipelineSpec`
/// during init.
struct PipelineSpec {
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let blendMode: BlendMode
}

class EffectsRenderer: NSObject, CAMetalDisplayLinkDelegate {

    // MARK: - Metal objects

    let metalDevice: MTLDevice
    let metalLayer: CAMetalLayer
    /// Serial queue this renderer's ticks + draw run on. Audio subscribers also
    /// receive on this queue so all effect state mutations are serialized here
    /// (no locks needed for per-effect state).
    let renderQueue: DispatchQueue

    /// Drives vsync-aligned `draw()` calls. CAMetalDisplayLink (macOS 14+) replaces
    /// the older CVDisplayLink + manual `metalLayer.nextDrawable()` pattern, which
    /// blocked ≈ one vsync per frame waiting for a free drawable. Here the drawable
    /// is delivered to the delegate callback already acquired, eliminating that wait.
    private var displayLink: CAMetalDisplayLink?

    private let commandQueue: MTLCommandQueue

    // MARK: - Unified pipeline + submission storage

    private var pipelines: [EffectType: MTLRenderPipelineState] = [:]
    private var submissions: [ObjectIdentifier: (EffectType, EffectMesh)] = [:]
    /// Per-effect GPU buffer cache. Only touched on `renderQueue` inside `draw`,
    /// so no lock is required — `submit` / `remove` only mutate `submissions`.
    private var buffers: [ObjectIdentifier: MTLBuffer] = [:]

    private var screenSize: SIMD2<Float> = .zero
    private var backingScaleFactor: CGFloat = 1.0

    private var frameClients: [ObjectIdentifier: (TimeInterval) -> Void] = [:]
    private let lock = NSLock()

    /// Order pipelines are drawn in each frame, derived from the registry's
    /// renderOrder values. Fixed at init time so the draw loop doesn't have
    /// to consult the registry every frame.
    private var drawOrder: [EffectType] = []

    // MARK: - Initialization

    init?(metalLayer: CAMetalLayer, screen: NSScreen?) {
        guard
            let device = metalLayer.device ?? MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { return nil }

        self.metalDevice   = device
        self.commandQueue  = queue
        self.metalLayer    = metalLayer
        let displayID = screen?.displayID ?? 0
        self.renderQueue  = DispatchQueue(label: "spectrawall.renderer.\(displayID)",
                                          qos: .userInteractive)
        metalLayer.device = device

        guard let library = device.makeDefaultLibrary() else { return nil }

        super.init()

        // Compile a pipeline for every registered effect. Caller is responsible
        // for calling EffectRegistry.bootstrap() before the first renderer is
        // built (AppDelegate.applicationDidFinishLaunching does this at app
        // launch). If the registry is empty the renderer still works, just
        // draws nothing.
        let registry = EffectRegistry.all
        for (type, descriptor) in registry {
            guard let pipeline = Self.makePipeline(device: device,
                                                   library: library,
                                                   spec: descriptor.pipelineSpec) else {
                AppLog.render.error("Failed to compile pipeline for \(type.rawValue, privacy: .public)")
                return nil
            }
            pipelines[type] = pipeline
        }

        drawOrder = registry.values
            .sorted { $0.renderOrder < $1.renderOrder }
            .map(\.type)

        AppLog.render.info(
            "EffectsRenderer initialized: displayID=\(displayID, privacy: .public) effects=\(self.drawOrder.count, privacy: .public)"
        )

        // CAMetalDisplayLink delivers callbacks on whichever runloop we add it to.
        // Adding to the main runloop in .common mode means the delegate fires on
        // main thread; we immediately hop to renderQueue (sync) so all effect-state
        // access stays serialized with audio subscribers (which also receive on
        // renderQueue). The sync call blocks main for the duration of one frame
        // worth of encoding (typically < 1ms since drawable is provided, not
        // acquired).
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        link.preferredFrameLatency = 2
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private static func makePipeline(device: MTLDevice,
                                     library: MTLLibrary,
                                     spec: PipelineSpec) -> MTLRenderPipelineState? {
        guard
            let vf = library.makeFunction(name: spec.vertexFunctionName),
            let ff = library.makeFunction(name: spec.fragmentFunctionName)
        else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction    = vf
        desc.fragmentFunction  = ff
        // MSAA disabled in this revision — CAMetalLayer's drawable texture is
        // single-sample, so MSAA would require an offscreen multisample texture
        // + resolve pass. Acceptable for now; effects use alpha-blended smoothstep
        // edges so visual difference is small.
        desc.rasterSampleCount = 1
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        if let att = desc.colorAttachments[0] {
            spec.blendMode.apply(to: att)
        }
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// Stop driving the renderer. Must be called before the renderer is released
    /// so the display link's strong reference to its delegate (us) is broken and
    /// no further callbacks fire after teardown.
    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
        AppLog.render.info("EffectsRenderer invalidated")
    }

    // MARK: - Configuration

    func setBackingScaleFactor(_ scale: CGFloat) {
        lock.lock(); backingScaleFactor = scale; lock.unlock()
    }

    /// Set the logical scene size that vertex coordinates are expressed in.
    /// Locked because it's written from main (window setup) and read from renderQueue.
    func setSceneSize(_ size: CGSize) {
        let v = SIMD2<Float>(Float(size.width), Float(size.height))
        lock.lock(); screenSize = v; lock.unlock()
    }

    // MARK: - Unified submission API

    /// Submit (or replace) an effect's geometry for the next frame.
    func submit(id: ObjectIdentifier, type: EffectType, mesh: EffectMesh) {
        lock.lock(); submissions[id] = (type, mesh); lock.unlock()
    }

    /// Drop an effect's geometry. Buffers associated with the id are pruned
    /// inside the next `draw()` pass.
    func remove(id: ObjectIdentifier) {
        lock.lock(); submissions.removeValue(forKey: id); lock.unlock()
    }

    // MARK: - Frame tick registry

    func addFrameClient(id: ObjectIdentifier, tick: @escaping (TimeInterval) -> Void) {
        lock.lock(); frameClients[id] = tick; lock.unlock()
    }

    func removeFrameClient(id: ObjectIdentifier) {
        lock.lock(); frameClients.removeValue(forKey: id); lock.unlock()
    }

    // MARK: - CAMetalDisplayLink delegate

    /// Fires on the main runloop (where we added the display link). Must commit a
    /// command buffer before returning — the framework invalidates the drawable on
    /// callback exit — so we hop to `renderQueue` synchronously and do the work there.
    @objc func metalDisplayLink(_ link: CAMetalDisplayLink,
                                needsUpdate update: CAMetalDisplayLink.Update) {
        let drawable = update.drawable
        let presentTime = update.targetPresentationTimestamp
        renderQueue.sync {
            self.draw(drawable: drawable, presentTime: presentTime)
        }
    }

    // MARK: - Draw entry point

    /// Called from the CAMetalDisplayLink delegate (hopping through renderQueue.sync
    /// so audio + render state mutations stay serialized). The drawable is provided
    /// by the framework — no `nextDrawable()` acquire, no per-frame blocking wait —
    /// and `presentTime` is the predicted vsync at which to flip.
    func draw(drawable: CAMetalDrawable, presentTime: CFTimeInterval) {
        let now = CACurrentMediaTime()
        lock.lock()
        let ticks = Array(frameClients.values)
        let sceneSizeSnap = screenSize
        let submissionsSnap = submissions
        let pipelinesSnap = pipelines
        lock.unlock()

        for tick in ticks { tick(now) }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture     = drawable.texture
        pass.colorAttachments[0].loadAction  = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.commit()
            return
        }

        var sceneSizeForShader = sceneSizeSnap
        encoder.setVertexBytes(&sceneSizeForShader, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        // Group submissions by type so we set the pipeline once per group.
        var byType: [EffectType: [(ObjectIdentifier, EffectMesh)]] = [:]
        for (id, payload) in submissionsSnap {
            byType[payload.0, default: []].append((id, payload.1))
        }

        for type in drawOrder {
            guard let pipeline = pipelinesSnap[type], let group = byType[type] else { continue }
            encoder.setRenderPipelineState(pipeline)
            for (id, mesh) in group {
                guard mesh.vertices.count >= 3 else { continue }
                let byteCount = mesh.vertices.count * MemoryLayout<EffectVertex>.stride
                let buf: MTLBuffer
                if let existing = buffers[id], existing.length >= byteCount {
                    existing.contents().copyMemory(from: mesh.vertices, byteCount: byteCount)
                    buf = existing
                } else {
                    guard let newBuf = metalDevice.makeBuffer(
                        bytes: mesh.vertices,
                        length: byteCount,
                        options: .storageModeShared
                    ) else { continue }
                    buffers[id] = newBuf
                    buf = newBuf
                }
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
                encoder.drawPrimitives(type: mesh.primitiveType, vertexStart: 0, vertexCount: mesh.vertices.count)
            }
        }

        // Prune buffers whose submissions have been removed since last frame.
        let activeIds = Set(submissionsSnap.keys)
        buffers = buffers.filter { activeIds.contains($0.key) }

        encoder.endEncoding()
        // CAMetalDisplayLink handles vsync timing internally; calling
        // `present(_:atTime:)` with it is explicitly disallowed and throws.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Backward compatibility typealias
// Remove after all call sites are updated to EffectsRenderer.
typealias BorderTrailRenderer = EffectsRenderer
