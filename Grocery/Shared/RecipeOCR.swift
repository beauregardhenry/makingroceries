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

extension RecipeOCR {
    /// Recognized text grouped into rows, so a receipt's item and its price (which Vision reads as
    /// separate pieces far apart) come back as one line.
    static func rows(in image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            if let first = rows.last?.first,
               abs(observation.boundingBox.midY - first.boundingBox.midY) < max(observation.boundingBox.height, first.boundingBox.height) * 0.6 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "  ")
        }
    }
}
