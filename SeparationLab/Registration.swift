import Foundation
import CoreGraphics
import Vision

enum ImageRegistration {
    private static func cgImage(_ image:GrayImage) throws -> CGImage {
        guard let provider=CGDataProvider(data:Data(image.pixels) as CFData),
              let cg=CGImage(width:image.width,height:image.height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:image.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {
            throw MeasureError.invalid("Could not prepare images for registration.")
        }
        return cg
    }
    static func shift(reference:GrayImage,target:GrayImage) throws -> CGPoint {
        let request=VNTranslationalImageRegistrationRequest(targetedCGImage:try cgImage(target),options:[:])
        let handler=VNImageRequestHandler(cgImage:try cgImage(reference),options:[:])
        try handler.perform([request])
        guard let transform=request.results?.first?.alignmentTransform else {
            throw MeasureError.invalid("Could not align the photograph with the first capture.")
        }
        // Vision returns target-to-reference translation in bottom-left coordinates.
        // Our point coordinates use the top-left origin and reference-to-target.
        let shift=CGPoint(x:-transform.tx,y:transform.ty)
        guard shift.x.isFinite,shift.y.isFinite,abs(shift.x)<Double(reference.width)*0.15,abs(shift.y)<Double(reference.height)*0.15 else {
            throw MeasureError.invalid("The phone moved too far between photographs.")
        }
        return shift
    }
}
