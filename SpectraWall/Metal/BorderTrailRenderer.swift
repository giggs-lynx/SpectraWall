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
}

class BorderTrailRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    private var screenSize: SIMD2<Float> = .zero
    private var backingScaleFactor: CGFloat = 1.0

    private(set) var trails: [ObjectIdentifier: TrailData] = [:]
    private var vertexBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    private let lock = NSLock()

    init?(mtkView: MTKView) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { return nil }

        self.device       = device
        self.commandQueue = queue

        mtkView.device               = device
        mtkView.framebufferOnly      = false
        mtkView.colorPixelFormat     = .bgra8Unorm
        mtkView.clearColor           = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isPaused                  = false
        mtkView.enableSetNeedsDisplay     = false
        mtkView.preferredFramesPerSecond  = 60
        mtkView.sampleCount          = 4

        guard
            let library      = device.makeDefaultLibrary(),
            let vertexFunc   = library.makeFunction(name: "border_vertex"),
            let fragmentFunc = library.makeFunction(name: "border_fragment")
        else { return nil }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction    = vertexFunc
        pipelineDesc.fragmentFunction  = fragmentFunc
        pipelineDesc.rasterSampleCount = 4
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let att = pipelineDesc.colorAttachments[0] else { return nil }
        att.isBlendingEnabled           = true
        att.rgbBlendOperation           = .add
        att.alphaBlendOperation         = .add
        att.sourceRGBBlendFactor        = .sourceAlpha
        att.destinationRGBBlendFactor   = .one
        att.sourceAlphaBlendFactor      = .sourceAlpha
        att.destinationAlphaBlendFactor = .one

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)
        else { return nil }

        self.pipelineState = pipelineState
        super.init()
    }

    func setBackingScaleFactor(_ scale: CGFloat) {
        backingScaleFactor = scale
    }

    // MARK: - Trail Updates

    func updateTrail(id: ObjectIdentifier, data: TrailData) {
        lock.lock()
        trails[id] = data
        lock.unlock()
    }

    func removeTrail(id: ObjectIdentifier) {
        lock.lock()
        trails.removeValue(forKey: id)
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        screenSize = SIMD2<Float>(
            Float(size.width  / backingScaleFactor),
            Float(size.height / backingScaleFactor)
        )
    }

    func draw(in view: MTKView) {
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

        lock.lock()
        let snapshot = trails
        lock.unlock()

        let activeIds = Set(snapshot.keys)
        vertexBuffers = vertexBuffers.filter { activeIds.contains($0.key) }

        if !snapshot.isEmpty {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBytes(&screenSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

            for (id, trailData) in snapshot {
                guard trailData.vertices.count >= 3 else { continue }

                let byteCount = trailData.vertices.count * MemoryLayout<TrailVertex>.stride
                let buf: MTLBuffer
                if let existing = vertexBuffers[id], existing.length >= byteCount {
                    existing.contents().copyMemory(from: trailData.vertices, byteCount: byteCount)
                    buf = existing
                } else {
                    guard let newBuf = device.makeBuffer(
                        bytes: trailData.vertices,
                        length: byteCount,
                        options: .storageModeShared
                    ) else { continue }
                    vertexBuffers[id] = newBuf
                    buf = newBuf
                }

                encoder.setVertexBuffer(buf, offset: 0, index: 0)
                encoder.drawPrimitives(
                    type: .triangleStrip,
                    vertexStart: 0,
                    vertexCount: trailData.vertices.count
                )
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
