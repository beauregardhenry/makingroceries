import CoreGraphics
import ImageIO
import Vision

/// Reads text from a photo of a recipe, on the device. Nothing is uploaded.
enum RecipeOCR {
    /// The recognized lines from top to bottom. Slow for a large photo, so call it off the main thread.
    static func lines(in image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
