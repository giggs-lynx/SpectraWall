//
//  BorderTrailRenderer.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//

import Metal
import MetalKit
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

class EffectsRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal objects

    let metalDevice: MTLDevice
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

    init?(mtkView: MTKView) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { return nil }

        self.metalDevice  = device
        self.commandQueue = queue

        mtkView.device                   = device
        mtkView.framebufferOnly          = false
        mtkView.colorPixelFormat         = .bgra8Unorm
        mtkView.clearColor               = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isPaused                 = false
        mtkView.enableSetNeedsDisplay    = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.sampleCount              = 4

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
            desc.rasterSampleCount = 4
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
    }

    // MARK: - Configuration

    func setBackingScaleFactor(_ scale: CGFloat) {
        backingScaleFactor = scale
    }

    /// Set the logical scene size that vertex coordinates are expressed in.
    /// This decouples the shader's normalization basis from the Metal drawable
    /// size (which AppKit may resize independently at app launch).
    func setSceneSize(_ size: CGSize) {
        screenSize = SIMD2<Float>(Float(size.width), Float(size.height))
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

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Intentionally a no-op. The shader's vertex normalization basis
        // (screenSize) is pinned to the scene size in points via setSceneSize();
        // it must not track the Metal drawable size because AppKit may resize
        // the drawable to stale values at app launch (e.g. half-size on a
        // 1x external display while the window's screen association is still
        // settling).
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        lock.lock()
        let ticks = Array(tickClients.values)
        lock.unlock()
        for tick in ticks { tick(now) }

        guard
            let drawable       = view.currentDrawable,
            let renderPassDesc = view.currentRenderPassDescriptor,
            let commandBuffer  = commandQueue.makeCommandBuffer()
        else { return }

        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            commandBuffer.commit()
            return
        }

        encoder.setVertexBytes(&screenSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

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
