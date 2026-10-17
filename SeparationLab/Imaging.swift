import UIKit
import MetalKit
import ImageIO

final class ImageProcessor {
    private let device = MTLCreateSystemDefaultDevice()
    private var pipeline: MTLComputePipelineState?
    private var queue: MTLCommandQueue?
    private(set) var backend = "CPU luminance · CPU subpixel fitting"
    init() {
        if let device, let function = device.makeDefaultLibrary()?.makeFunction(name: "luminance") {
            pipeline = try? device.makeComputePipelineState(function: function)
            queue = device.makeCommandQueue()
        }
    }
    func decode(_ data: Data) throws -> CGImage {
        // Normalize EXIF orientation before point selection and subsequent analysis.
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let original = CGImageSourceCreateImageAtIndex(source,0,nil) else {
            throw MeasureError.invalid("Could not decode the captured photograph.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any]
        let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        let ci = CIImage(cgImage: original).oriented(forExifOrientation: orientation)
        guard let normalized = CIContext().createCGImage(ci,from:ci.extent) else {
            throw MeasureError.invalid("Could not orient the photograph.")
        }
        return normalized
    }
    func gray(_ image: CGImage) throws -> GrayImage {
        let w = image.width, h = image.height
        if let device, let pipeline, let queue {
            do {
                let input = try MTKTextureLoader(device:device).newTexture(cgImage:image,options:[.SRGB:false])
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Unorm,width:w,height:h,mipmapped:false)
                descriptor.usage = [.shaderWrite,.shaderRead]; descriptor.storageMode = .shared
                if let output = device.makeTexture(descriptor:descriptor), let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() {
                    encoder.setComputePipelineState(pipeline); encoder.setTexture(input,index:0); encoder.setTexture(output,index:1)
                    let tw = pipeline.threadExecutionWidth, th = min(16,pipeline.maxTotalThreadsPerThreadgroup/tw)
                    encoder.dispatchThreads(MTLSize(width:w,height:h,depth:1),threadsPerThreadgroup:MTLSize(width:tw,height:th,depth:1))
                    encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                    if command.status == .completed {
                        var bytes = [UInt8](repeating:0,count:w*h)
                        bytes.withUnsafeMutableBytes { output.getBytes($0.baseAddress!,bytesPerRow:w,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0) }
                        backend = "Metal luminance · CPU subpixel fitting"
                        return GrayImage(width:w,height:h,pixels:bytes)
                    }
                }
            } catch { /* Preserve a functioning, explicit CPU fallback. */ }
        }
        backend = "CPU luminance · CPU subpixel fitting"
        var bytes = [UInt8](repeating:0,count:w*h)
        let success = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let context = CGContext(data:ptr.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard success else { throw MeasureError.invalid("Could not create the analysis image.") }
        return GrayImage(width:w,height:h,pixels:bytes)
    }
}
