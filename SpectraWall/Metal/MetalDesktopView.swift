//
//  MetalDesktopView.swift
//  SpectraWall
//
//  A minimal NSView whose backing layer is a CAMetalLayer. Replaces MTKView so the
//  renderer can be driven by a CVDisplayLink on a private serial queue instead of
//  MTKView's internal display loop (which fires on the main thread and stalls when
//  SwiftUI/AppKit blocks main with Settings panel / popover construction).
//

import AppKit
import Metal
import QuartzCore

final class MetalDesktopView: NSView {

    let metalLayer = CAMetalLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.device          = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat     = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque        = false
        // Default is 3 (triple buffered). Lower to 2 so `nextDrawable()` waits less
        // when GPU is contended by the CA compositor during SwiftUI Settings work —
        // shallower queue means previous frame finishes sooner.
        metalLayer.maximumDrawableCount = 2
        // Use our CAMetalLayer as the view's backing layer directly. Required when
        // wantsLayer=true and we don't want the system to wrap it in a CALayer.
        layer = metalLayer
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update layer's drawable size + backing-scale to match the host window/screen.
    /// Called from window setup; avoid setting drawableSize repeatedly with the same
    /// value (each set causes Core Animation to drop the existing drawable pool).
    func setLayerSize(_ size: CGSize, scale: CGFloat) {
        metalLayer.contentsScale = scale
        let pxSize = CGSize(width: size.width * scale, height: size.height * scale)
        if metalLayer.drawableSize != pxSize {
            metalLayer.drawableSize = pxSize
        }
    }
}
