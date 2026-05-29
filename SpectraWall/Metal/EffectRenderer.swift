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
    /// 1 = single-sample (no MSAA); 4 = 4× MSAA with offscreen multisample
    /// target + resolve into the drawable. Fixed at init time — pipelines
    /// are compiled against this count and can't be rebuilt without
    /// reconstructing the renderer.
    let sampleCount: Int
    /// Offscreen multisample render target, only allocated when sampleCount > 1.
    /// Lazily (re)created in `draw()` to match the current drawable size.
    /// `.memoryless` on Apple Silicon keeps it in tile memory only (no DRAM).
    private var msaaTexture: MTLTexture?
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
    /// rates are an integer ratio (60Hz × 2 = 120Hz ProMotion).
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

    /// Monotonic time of the most recent CAMetalDisplayLink callback. Written
    /// on the dedicated displayLink thread; read by the render watchdog on main.
    /// The benign unsynchronised Double read on 64-bit ARM is intentional —
    /// a stale value just delays watchdog recovery by one tick (≤3 s).
    nonisolated(unsafe) private(set) var lastCallbackTime: CFTimeInterval = 0

    private let commandQueue: MTLCommandQueue

    // MARK: - Unified pipeline + submission storage

    private var pipelines: [EffectType: MTLRenderPipelineState] = [:]
    private var submissions: [ObjectIdentifier: (EffectType, EffectMesh)] = [:]
    /// Per-effect GPU buffer cache. Only touched on `renderQueue` inside `draw`,
    /// so no lock is required — `submit` / `remove` only mutate `submissions`.
    private var buffers: [ObjectIdentifier: MTLBuffer] = [:]

    // MARK: - Debug overlay channel

    /// Built-in flat-colour pipeline for the debug overlay, compiled once at init
    /// independently of the effect registry (so it never appears in the effect
    /// picker). Drawn on top of all effects via alpha blend.
    private var debugPipeline: MTLRenderPipelineState?
    /// Debug geometry submitted by effects via `submitDebug`. Drawn last each
    /// frame when `isDebugEnabled`. Keyed by the contributing effect's id.
    private var debugSubmissions: [ObjectIdentifier: EffectMesh] = [:]
    private var debugBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    /// Global debug master, fanned in from AppSettings.debugEnabled. Read +
    /// written only on `renderQueue`, so a plain Bool is race-free here.
    private(set) var isDebugEnabled = false

    private var screenSize: SIMD2<Float> = .zero

    private var frameClients: [ObjectIdentifier: (TimeInterval) -> Void] = [:]

    /// Identifies our `renderQueue` from any thread so mutators can decide
    /// whether to mutate directly (when already on renderQueue, e.g. an
    /// effect's onTick) or hop via async dispatch (when called from main
    /// during scene setup / teardown). Replaces the previous NSLock-guarded
    /// dual-thread access; mutations are now strictly serialized through
    /// the queue itself rather than a lock.
    private static let renderQueueKey = DispatchSpecificKey<UInt8>()

    /// Per-type fallback order from the registry's renderOrder. Only used for
    /// submissions not covered by `orderedIDs`.
    private var drawOrder: [EffectType] = []

    /// Back-to-front paint order (effect ids) pushed by EffectsCoordinator,
    /// mirroring the user's effect-row order. Source of truth for stacking.
    private var orderedIDs: [ObjectIdentifier] = []

    // MARK: - Initialization

    init?(metalLayer: CAMetalLayer, screen: NSScreen?, sampleCount: Int = 1) {
        guard
            let device = metalLayer.device ?? MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { return nil }

        self.metalDevice   = device
        self.commandQueue  = queue
        self.metalLayer    = metalLayer
        self.sampleCount   = sampleCount
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
                                                   spec: descriptor.pipelineSpec,
                                                   sampleCount: sampleCount) else {
                AppLog.render.error("Failed to compile pipeline for \(type.rawValue, privacy: .public)")
                return nil
            }
            pipelines[type] = pipeline
        }

        // Built-in debug pipeline (not registry-driven). Flat colour, alpha
        // blended, drawn on top. Missing shaders just disable the overlay.
        debugPipeline = Self.makePipeline(
            device: device,
            library: library,
            spec: PipelineSpec(vertexFunctionName: "debug_vertex",
                               fragmentFunctionName: "debug_fragment",
                               blendMode: .alphaBlend),
            sampleCount: sampleCount
        )

        drawOrder = registry.values
            .sorted { $0.renderOrder < $1.renderOrder }
            .map(\.type)

        AppLog.render.info("""
            Renderer init: display=\(displayID, privacy: .public) \
            effects=\(self.drawOrder.count, privacy: .public)
            """)

        // CAMetalDisplayLink delivers callbacks on whichever runloop we add it to.
        // We start a dedicated thread per renderer and add the link to that
        // thread's runloop so:
        //   1. Dual-screen setups don't have both displayLinks contending for
        //      the main runloop (which caused cb-gap-max ≈ 600ms on the 60Hz
        //      screen in practice).
        //   2. main thread is free to handle SwiftUI / AppKit / audio listener
        //      callbacks without delaying vsync delivery.
        // The callback still hops to renderQueue.sync to keep effect-state
        // mutations serialized with audio subscribers.
        startDisplayLinkOnDedicatedThread(for: metalLayer)
    }

    private func startDisplayLinkOnDedicatedThread(for metalLayer: CAMetalLayer) {
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        link.preferredFrameLatency = 2
        self.displayLink = link

        let threadName = "spectrawall.displaylink.\(displayID)"
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.displayLinkRunLoop = CFRunLoopGetCurrent()
            link.add(to: .current, forMode: .common)
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = threadName
        thread.start()
        self.displayLinkThread = thread
    }

    private static func makePipeline(device: MTLDevice,
                                     library: MTLLibrary,
                                     spec: PipelineSpec,
                                     sampleCount: Int) -> MTLRenderPipelineState? {
        guard
            let vf = library.makeFunction(name: spec.vertexFunctionName),
            let ff = library.makeFunction(name: spec.fragmentFunctionName)
        else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction    = vf
        desc.fragmentFunction  = ff
        desc.rasterSampleCount = sampleCount
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

    // MARK: - Debug overlay API

    /// Flip the global debug master for this renderer. Turning it off clears
    /// any pending debug geometry so effects don't have to manage the
    /// transition — they simply stop submitting once `isDebugEnabled` is false.
    func setDebugEnabled(_ enabled: Bool) {
        onRenderQueue(.async) {
            self.isDebugEnabled = enabled
            if !enabled { self.debugSubmissions.removeAll() }
        }
    }

    /// Submit (or replace) an effect's debug geometry for the next frame. Drawn
    /// on top of everything via the debug pipeline when `isDebugEnabled`.
    func submitDebug(id: ObjectIdentifier, mesh: EffectMesh) {
        onRenderQueue(.async) { self.debugSubmissions[id] = mesh }
    }

    /// Drop an effect's debug geometry.
    func removeDebug(id: ObjectIdentifier) {
        onRenderQueue(.async) { self.debugSubmissions.removeValue(forKey: id) }
    }

    /// Set the back-to-front paint order as effect ids (last = on top).
    func setDrawOrder(_ ids: [ObjectIdentifier]) {
        onRenderQueue(.async) { self.orderedIDs = ids }
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
        lastCallbackTime = CACurrentMediaTime()
        metrics.recordCallback(at: lastCallbackTime)
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
        let ticks = Array(frameClients.values)
        for tick in ticks { tick(now) }
        let sceneSizeSnap = screenSize
        let submissionsSnap = submissions
        let orderSnap = orderedIDs
        let pipelinesSnap = pipelines
        let debugSnap = isDebugEnabled ? debugSubmissions : [:]

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let pass = makeRenderPassDescriptor(drawable: drawable)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.commit()
            return
        }

        var sceneSizeForShader = sceneSizeSnap
        encoder.setVertexBytes(&sceneSizeForShader, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        // While debugging, an effect that contributes debug geometry is replaced
        // by its skeleton (pure wireframe) — hide its normal mesh. Effects with
        // no debug geometry keep rendering normally.
        let normalSubmissions = debugSnap.isEmpty
            ? submissionsSnap
            : submissionsSnap.filter { debugSnap[$0.key] == nil }
        encodeSubmissions(normalSubmissions, order: orderSnap, pipelines: pipelinesSnap, encoder: encoder)

        let activeIds = Set(submissionsSnap.keys)
        buffers = buffers.filter { activeIds.contains($0.key) }

        // Debug overlay on top of all effects.
        if !debugSnap.isEmpty, let debugPipeline {
            encodeDebug(debugSnap, pipeline: debugPipeline, encoder: encoder)
        }
        let activeDebugIds = Set(debugSnap.keys)
        debugBuffers = debugBuffers.filter { activeDebugIds.contains($0.key) }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        metrics.recordFrame(start: frameStart, end: CACurrentMediaTime())
    }

    private func makeRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        if sampleCount > 1 {
            let w = drawable.texture.width
            let h = drawable.texture.height
            if msaaTexture?.width != w || msaaTexture?.height != h {
                let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: w, height: h,
                    mipmapped: false
                )
                texDesc.textureType = .type2DMultisample
                texDesc.sampleCount = sampleCount
                texDesc.usage = .renderTarget
                texDesc.storageMode = metalDevice.hasUnifiedMemory ? .memoryless : .private
                msaaTexture = metalDevice.makeTexture(descriptor: texDesc)
            }
            pass.colorAttachments[0].texture = msaaTexture
            pass.colorAttachments[0].resolveTexture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return pass
    }

    private func encodeSubmissions(
        _ submissions: [ObjectIdentifier: (EffectType, EffectMesh)],
        order: [ObjectIdentifier],
        pipelines: [EffectType: MTLRenderPipelineState],
        encoder: MTLRenderCommandEncoder
    ) {
        // Paint in the layer order the coordinator pushed. Submissions not yet
        // in `order` (an effect that submitted before the coordinator pushed a
        // refreshed order) are appended via the per-type fallback so they're
        // never dropped.
        var painted = Set<ObjectIdentifier>()
        var sequence = order.filter { submissions[$0] != nil }
        painted.formUnion(sequence)
        if painted.count < submissions.count {
            sequence += submissions.keys
                .filter { !painted.contains($0) }
                .sorted { typeRank(submissions[$0]?.0) < typeRank(submissions[$1]?.0) }
        }

        var boundType: EffectType?
        for id in sequence {
            guard let (type, mesh) = submissions[id], mesh.vertices.count >= 3,
                  let pipeline = pipelines[type] else { continue }
            if boundType != type {
                encoder.setRenderPipelineState(pipeline)
                boundType = type
            }
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
            encoder.drawPrimitives(type: mesh.primitiveType,
                                   vertexStart: 0,
                                   vertexCount: mesh.vertices.count)
        }
    }

    private func typeRank(_ type: EffectType?) -> Int {
        guard let type, let idx = drawOrder.firstIndex(of: type) else { return .max }
        return idx
    }

    /// Encode every debug submission with the single flat-colour debug pipeline.
    /// Mirrors `encodeSubmissions`' buffer cache, but one pipeline and no order
    /// (debug geometry is additive-free flat fill, draw order is irrelevant).
    private func encodeDebug(
        _ submissions: [ObjectIdentifier: EffectMesh],
        pipeline: MTLRenderPipelineState,
        encoder: MTLRenderCommandEncoder
    ) {
        encoder.setRenderPipelineState(pipeline)
        for (id, mesh) in submissions {
            guard mesh.vertices.count >= 3 else { continue }
            let byteCount = mesh.vertices.count * MemoryLayout<EffectVertex>.stride
            let buf: MTLBuffer
            if let existing = debugBuffers[id], existing.length >= byteCount {
                existing.contents().copyMemory(from: mesh.vertices, byteCount: byteCount)
                buf = existing
            } else {
                guard let newBuf = metalDevice.makeBuffer(
                    bytes: mesh.vertices,
                    length: byteCount,
                    options: .storageModeShared
                ) else { continue }
                debugBuffers[id] = newBuf
                buf = newBuf
            }
            encoder.setVertexBuffer(buf, offset: 0, index: 0)
            encoder.drawPrimitives(type: mesh.primitiveType,
                                   vertexStart: 0,
                                   vertexCount: mesh.vertices.count)
        }
    }
}
