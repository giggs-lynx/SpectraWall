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

class EffectRenderer: NSObject, CAMetalDisplayLinkDelegate {

    // MARK: - Metal objects

    let metalDevice: MTLDevice
    let metalLayer: CAMetalLayer
    let displayID: CGDirectDisplayID
    /// Serial queue this renderer's ticks + draw run on. Audio subscribers also
    /// receive on this queue so all effect state mutations are serialized here
    /// (no locks needed for per-effect state).
    let renderQueue: DispatchQueue

    /// Drives vsync-aligned `draw()` calls. CAMetalDisplayLink (macOS 14+) replaces
    /// the older CVDisplayLink + manual `metalLayer.nextDrawable()` pattern, which
    /// blocked ≈ one vsync per frame waiting for a free drawable. Here the drawable
    /// is delivered to the delegate callback already acquired, eliminating that wait.
    private var displayLink: CAMetalDisplayLink?

    /// Dedicated thread the displayLink runs its callbacks on. Each renderer owns
    /// its own thread so dual-screen setups don't share a runloop — sharing
    /// `.main` causes the two callbacks to starve each other when their refresh
    /// rates are an integer ratio (60Hz × 2 = 120Hz ProMotion). See
    /// `findings_dual_screen_displaylink.md` for the cb-gap data that pinpointed
    /// this.
    private var displayLinkThread: Thread?

    /// CFRunLoop of `displayLinkThread`, stashed so `invalidate()` can stop it
    /// from another thread. CFRunLoopRun() blocks indefinitely; the matching
    /// CFRunLoopStop() is what lets the thread exit.
    private var displayLinkRunLoop: CFRunLoop?

    /// Per-renderer perf meter. Always on; logs via AppLog.render at info
    /// level which is zero-cost without a subscriber. See RenderMetrics.swift
    /// for the rolling-window definition and the `log show` invocation that
    /// surfaces the heartbeat line.
    private let metrics: RenderMetrics

    private let commandQueue: MTLCommandQueue

    // MARK: - Unified pipeline + submission storage

    private var pipelines: [EffectType: MTLRenderPipelineState] = [:]
    private var submissions: [ObjectIdentifier: (EffectType, EffectMesh)] = [:]
    /// Per-effect GPU buffer cache. Only touched on `renderQueue` inside `draw`,
    /// so no lock is required — `submit` / `remove` only mutate `submissions`.
    private var buffers: [ObjectIdentifier: MTLBuffer] = [:]

    private var screenSize: SIMD2<Float> = .zero

    private var frameClients: [ObjectIdentifier: (TimeInterval) -> Void] = [:]

    /// Identifies our `renderQueue` from any thread so mutators can decide
    /// whether to mutate directly (when already on renderQueue, e.g. an
    /// effect's onTick) or hop via async dispatch (when called from main
    /// during scene setup / teardown). Replaces the previous NSLock-guarded
    /// dual-thread access; mutations are now strictly serialized through
    /// the queue itself rather than a lock.
    private static let renderQueueKey = DispatchSpecificKey<UInt8>()

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
        self.displayID = displayID
        self.metrics = RenderMetrics(displayID: displayID)
        self.renderQueue  = DispatchQueue(label: "spectrawall.renderer.\(displayID)",
                                          qos: .userInteractive)
        renderQueue.setSpecific(key: Self.renderQueueKey, value: 1)
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
            "EffectRenderer initialized: displayID=\(displayID, privacy: .public) effects=\(self.drawOrder.count, privacy: .public)"
        )

        // CAMetalDisplayLink delivers callbacks on whichever runloop we add it to.
        // We start a dedicated thread per renderer and add the link to that
        // thread's runloop so:
        //   1. Dual-screen setups don't have both displayLinks contending for
        //      the main runloop (which caused cb-gap-max ≈ 600ms on the 60Hz
        //      screen — see findings_dual_screen_displaylink.md).
        //   2. main thread is free to handle SwiftUI / AppKit / audio listener
        //      callbacks without delaying vsync delivery.
        // The callback still hops to renderQueue.sync to keep effect-state
        // mutations serialized with audio subscribers.
        startDisplayLinkOnDedicatedThread(for: metalLayer)
    }

    private func startDisplayLinkOnDedicatedThread(for metalLayer: CAMetalLayer) {
        let threadName = "spectrawall.displaylink.\(displayID)"
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.displayLinkRunLoop = CFRunLoopGetCurrent()
            let link = CAMetalDisplayLink(metalLayer: metalLayer)
            link.delegate = self
            link.preferredFrameLatency = 2
            link.add(to: .current, forMode: .common)
            self.displayLink = link
            // Block this thread on its CFRunLoop indefinitely. The displayLink
            // ticks the runloop on every vsync; teardown calls CFRunLoopStop
            // (from invalidate(), on whichever queue) to unblock and let the
            // thread exit. Don't replace this with `while !cancelled { RunLoop
            // .run(mode:before:) }` — that idiom spins at 100% CPU when no
            // input source has events queued, because run(mode:before:)
            // returns immediately in that case.
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = threadName
        thread.start()
        self.displayLinkThread = thread
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
        // Unblock the dedicated thread's CFRunLoopRun() so the closure
        // returns and the thread exits. Stop the runloop *before* dropping
        // the reference; otherwise we lose the only handle on it.
        if let runLoop = displayLinkRunLoop {
            CFRunLoopStop(runLoop)
        }
        displayLinkRunLoop = nil
        displayLinkThread = nil
        AppLog.render.info("EffectRenderer invalidated")
    }

    deinit {
        // Safety net: AppDelegate's window teardown always calls invalidate()
        // before releasing us, but if anything ever drops the last reference
        // without that, make sure the dedicated thread doesn't zombie.
        if displayLinkThread != nil {
            invalidate()
        }
    }

    // MARK: - Configuration

    /// Set the logical scene size that vertex coordinates are expressed in.
    /// Called from main during window setup; dispatch sync to guarantee the
    /// first `draw()` sees a non-zero `screenSize` even if it fires moments
    /// after this returns.
    func setSceneSize(_ size: CGSize) {
        let v = SIMD2<Float>(Float(size.width), Float(size.height))
        onRenderQueue(.sync) { self.screenSize = v }
    }

    // MARK: - Unified submission API

    /// Submit (or replace) an effect's geometry for the next frame.
    func submit(id: ObjectIdentifier, type: EffectType, mesh: EffectMesh) {
        onRenderQueue(.async) { self.submissions[id] = (type, mesh) }
    }

    /// Drop an effect's geometry. Buffers associated with the id are pruned
    /// inside the next `draw()` pass.
    func remove(id: ObjectIdentifier) {
        onRenderQueue(.async) { self.submissions.removeValue(forKey: id) }
    }

    // MARK: - Frame tick registry

    func addFrameClient(id: ObjectIdentifier, tick: @escaping (TimeInterval) -> Void) {
        onRenderQueue(.async) { self.frameClients[id] = tick }
    }

    func removeFrameClient(id: ObjectIdentifier) {
        onRenderQueue(.async) { self.frameClients.removeValue(forKey: id) }
    }

    // MARK: - Dispatch helper

    private enum DispatchMode { case sync, async }

    /// Run `body` on `renderQueue`. If already on `renderQueue` (e.g. an
    /// effect's onTick reaches in to call `submit`), run inline so the
    /// mutation lands before the current frame finishes drawing — async
    /// dispatch would push it to the next frame. From any other queue,
    /// async dispatch unless the caller explicitly needs sync semantics
    /// (only `setSceneSize` does, to satisfy first-draw initialization).
    private func onRenderQueue(_ mode: DispatchMode, _ body: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Self.renderQueueKey) == 1 {
            body()
            return
        }
        switch mode {
        case .sync:  renderQueue.sync(execute: body)
        case .async: renderQueue.async(execute: body)
        }
    }

    // MARK: - CAMetalDisplayLink delegate

    /// Fires on the main runloop (where we added the display link). Must commit a
    /// command buffer before returning — the framework invalidates the drawable on
    /// callback exit — so we hop to `renderQueue` synchronously and do the work there.
    @objc func metalDisplayLink(_ link: CAMetalDisplayLink,
                                needsUpdate update: CAMetalDisplayLink.Update) {
        metrics.recordCallback(at: CACurrentMediaTime())
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
        let frameStart = CACurrentMediaTime()
        let now = frameStart
        // We're already on renderQueue (via the displayLink delegate's sync
        // hop) and every mutator now serializes through this same queue, so
        // direct access is safe — no lock or snapshot required. Tick clients
        // can mutate submissions reentrantly via their submit/remove calls;
        // those run inline (same-queue fast path in onRenderQueue) so the
        // mutations land in time for the draw loop below.
        let ticks = Array(frameClients.values)
        for tick in ticks { tick(now) }
        let sceneSizeSnap = screenSize
        let submissionsSnap = submissions
        let pipelinesSnap = pipelines

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

        metrics.recordFrame(start: frameStart, end: CACurrentMediaTime())
    }
}
