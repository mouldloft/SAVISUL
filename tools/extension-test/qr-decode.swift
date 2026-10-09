// Prints the text of the first QR code found in an image: qr-decode <file.png>
import CoreImage
import Foundation

guard CommandLine.arguments.count > 1,
      let image = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write(Data("usage: qr-decode <image>\n".utf8))
    exit(2)
}
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
let codes = detector?.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString } ?? []
guard let first = codes.first else { exit(1) }
print(first)
