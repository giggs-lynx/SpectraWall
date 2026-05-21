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

import AppKit
import Metal
import QuartzCore
import simd

struct TrailVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
    var alpha: Float
    var edgeDist: Float
}

struct TrailData {
    var vertices: [TrailVertex]
    var primitiveType: MTLPrimitiveType = .triangleStrip
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
    private let borderPipelineState: MTLRenderPipelineState    // additive; border trail
    private let spectrumPipelineState: MTLRenderPipelineState  // alpha blend; spectrum bars
    private let orbPipelineState: MTLRenderPipelineState       // additive; orb glow

    private var screenSize: SIMD2<Float> = .zero
    private var backingScaleFactor: CGFloat = 1.0

    // MARK: - Per-effect data and buffer caches

    private(set) var trails: [ObjectIdentifier: TrailData] = [:]       // Border
    private var spectrumData: [ObjectIdentifier: TrailData] = [:]      // Spectrum
    private var orbData: [ObjectIdentifier: TrailData] = [:]           // Orb

    private var borderBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    private var spectrumBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    private var orbBuffers: [ObjectIdentifier: MTLBuffer] = [:]

    private var tickClients: [ObjectIdentifier: (TimeInterval) -> Void] = [:]
    private let lock = NSLock()

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

        // Make sure layer + device agree (it's harmless if already set).
        metalLayer.device = device

        guard let library = device.makeDefaultLibrary() else { return nil }

        // Helper that builds a pipeline with named shader functions and a blend configurator.
        func makePipeline(vertex: String, fragment: String,
                          blend: (MTLRenderPipelineColorAttachmentDescriptor) -> Void)
            -> MTLRenderPipelineState?
        {
            guard
                let vf = library.makeFunction(name: vertex),
                let ff = library.makeFunction(name: fragment)
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
                att.isBlendingEnabled = true
                blend(att)
            }
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        let additive: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = { att in
            att.rgbBlendOperation           = .add
            att.alphaBlendOperation         = .add
            att.sourceRGBBlendFactor        = .sourceAlpha
            att.destinationRGBBlendFactor   = .one
            att.sourceAlphaBlendFactor      = .sourceAlpha
            att.destinationAlphaBlendFactor = .one
        }
        let alphaBlend: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = { att in
            att.rgbBlendOperation           = .add
            att.alphaBlendOperation         = .add
            att.sourceRGBBlendFactor        = .sourceAlpha
            att.destinationRGBBlendFactor   = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor      = .sourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        guard
            let bp = makePipeline(vertex: "border_vertex",   fragment: "border_fragment",   blend: additive),
            let sp = makePipeline(vertex: "spectrum_vertex",  fragment: "spectrum_fragment", blend: alphaBlend),
            let op = makePipeline(vertex: "orb_vertex",       fragment: "orb_fragment",      blend: additive)
        else { return nil }

        self.borderPipelineState   = bp
        self.spectrumPipelineState = sp
        self.orbPipelineState      = op
        super.init()

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

    /// Stop driving the renderer. Must be called before the renderer is released
    /// so the display link's strong reference to its delegate (us) is broken and
    /// no further callbacks fire after teardown.
    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
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

    // MARK: - Border API

    func updateTrail(id: ObjectIdentifier, data: TrailData) {
        lock.lock(); trails[id] = data; lock.unlock()
    }

    func removeTrail(id: ObjectIdentifier) {
        lock.lock(); trails.removeValue(forKey: id); lock.unlock()
    }

    // MARK: - Spectrum API

    func updateSpectrum(id: ObjectIdentifier, data: TrailData) {
        lock.lock(); spectrumData[id] = data; lock.unlock()
    }

    func removeSpectrum(id: ObjectIdentifier) {
        lock.lock(); spectrumData.removeValue(forKey: id); lock.unlock()
    }

    // MARK: - Orb API

    func updateOrb(id: ObjectIdentifier, data: TrailData) {
        lock.lock(); orbData[id] = data; lock.unlock()
    }

    func removeOrb(id: ObjectIdentifier) {
        lock.lock(); orbData.removeValue(forKey: id); lock.unlock()
    }

    // MARK: - Tick registry

    func registerTickClient(id: ObjectIdentifier, tick: @escaping (TimeInterval) -> Void) {
        lock.lock(); tickClients[id] = tick; lock.unlock()
    }

    func unregisterTickClient(id: ObjectIdentifier) {
        lock.lock(); tickClients.removeValue(forKey: id); lock.unlock()
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
        let ticks = Array(tickClients.values)
        let sceneSizeSnap = screenSize
        lock.unlock()
        for tick in ticks { tick(now) }
        // No nextDrawable() — caller supplied an already-acquired drawable.
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

        lock.lock()
        let borderSnap   = trails
        let spectrumSnap = spectrumData
        let orbSnap      = orbData
        lock.unlock()

        drawEffects(snapshot: borderSnap,   pipeline: borderPipelineState,
                    buffers: &borderBuffers,   encoder: encoder)
        drawEffects(snapshot: spectrumSnap, pipeline: spectrumPipelineState,
                    buffers: &spectrumBuffers, encoder: encoder)
        drawEffects(snapshot: orbSnap,      pipeline: orbPipelineState,
                    buffers: &orbBuffers,      encoder: encoder)

        encoder.endEncoding()
        // CAMetalDisplayLink handles vsync timing internally; calling
        // `present(_:atTime:)` with it is explicitly disallowed and throws.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Private helpers

    private func drawEffects(
        snapshot: [ObjectIdentifier: TrailData],
        pipeline: MTLRenderPipelineState,
        buffers: inout [ObjectIdentifier: MTLBuffer],
        encoder: MTLRenderCommandEncoder
    ) {
        guard !snapshot.isEmpty else { return }

        let activeIds = Set(snapshot.keys)
        buffers = buffers.filter { activeIds.contains($0.key) }

        encoder.setRenderPipelineState(pipeline)

        for (id, data) in snapshot {
            guard data.vertices.count >= 3 else { continue }

            let byteCount = data.vertices.count * MemoryLayout<TrailVertex>.stride
            let buf: MTLBuffer
            if let existing = buffers[id], existing.length >= byteCount {
                existing.contents().copyMemory(from: data.vertices, byteCount: byteCount)
                buf = existing
            } else {
                guard let newBuf = metalDevice.makeBuffer(
                    bytes: data.vertices,
                    length: byteCount,
                    options: .storageModeShared
                ) else { continue }
                buffers[id] = newBuf
                buf = newBuf
            }

            encoder.setVertexBuffer(buf, offset: 0, index: 0)
            encoder.drawPrimitives(type: data.primitiveType, vertexStart: 0, vertexCount: data.vertices.count)
        }
    }
}

// MARK: - Backward compatibility typealias
// Remove after all call sites are updated to EffectsRenderer.
typealias BorderTrailRenderer = EffectsRenderer
