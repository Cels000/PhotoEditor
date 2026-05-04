import CoreImage
import Metal
import MetalKit
import SwiftUI

/// MTKView-backed live preview. Pulls the latest cooked CIImage from the
/// renderer on each draw call and blits it via the renderer's CIContext.
struct CameraPreviewView: UIViewRepresentable {

    let renderer: CameraPreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.contentMode = .scaleAspectFit
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer = renderer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: CameraPreviewRenderer
        private let commandQueue: MTLCommandQueue?
        private let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

        init(renderer: CameraPreviewRenderer) {
            self.renderer = renderer
            self.commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let image = renderer.latestSnapshot() else { return }

            // Aspect-fit the source into the drawable.
            let drawableSize = view.drawableSize
            let scale = min(drawableSize.width / image.extent.width,
                            drawableSize.height / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = (drawableSize.width - scaled.extent.width) / 2
            let dy = (drawableSize.height - scaled.extent.height) / 2
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))

            // Clear background to canvas-black for letterbox bands.
            let bg = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            view.clearColor = bg

            // Render via CIContext fast path.
            renderer.ciContext.render(
                positioned,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawableSize),
                colorSpace: outputColorSpace
            )

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
