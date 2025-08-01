import Vision
import AppKit

class ScreenOCR {
    static let shared = ScreenOCR()

    func captureScreenAndExtractText(completion: @escaping (String) -> Void) {
        // Capture screenshot of the entire screen
        guard let cgImage = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else {
            print("Failed to capture screen image.")
            completion("")
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("Failed to recognize text.")
                completion("")
                return
            }

            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            let fullText = recognizedStrings.joined(separator: " ")
            completion(fullText)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("Error performing OCR request: \(error)")
                completion("")
            }
        }
    }
}
