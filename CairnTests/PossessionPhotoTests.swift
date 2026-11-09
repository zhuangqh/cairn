import XCTest
import SwiftData
import ImageIO
import UniformTypeIdentifiers
@testable import Cairn

@MainActor
final class PossessionPhotoTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: - Backup

    func testRestorePreservesPossessionPhoto() throws {
        let context = container.mainContext
        let photo = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        context.insert(Possession(
            name: "Camera",
            category: .electronics,
            purchasePrice: 2_300,
            purchaseCurrency: "EUR",
            photoData: photo
        ))
        context.insert(Possession(name: "Car", category: .vehicle, purchasePrice: 9_000, purchaseCurrency: "USD"))
        try context.save()

        let backup = try BackupService.makeBackup(in: context, homeCurrency: "USD")
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: backup, context: other.mainContext)

        let restored = try other.mainContext.fetch(FetchDescriptor<Possession>())
        XCTAssertEqual(restored.first { $0.name == "Camera" }?.photoData, photo)
        XCTAssertNil(restored.first { $0.name == "Car" }?.photoData)
    }

    func testRestoreVersion4PossessionWithoutPhotoSucceeds() throws {
        let json = Data("""
        {
          "version": 4,
          "exportedAt": "2026-01-01T00:00:00Z",
          "members": [],
          "accounts": [],
          "holdings": [],
          "snapshots": [],
          "fxRates": [],
          "possessions": [{
            "id": "6F1C2E4A-2B3D-4C5E-8F90-1A2B3C4D5E6F",
            "name": "Laptop",
            "categoryRawValue": "electronics",
            "purchasePrice": 1999,
            "purchaseCurrency": "USD",
            "purchaseDate": "2025-03-01T00:00:00Z",
            "createdAt": "2025-03-01T00:00:00Z"
          }]
        }
        """.utf8)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: json, context: other.mainContext)

        let restored = try other.mainContext.fetch(FetchDescriptor<Possession>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.purchasePrice, 1_999)
        XCTAssertNil(restored.first?.photoData)
    }

    // MARK: - Photo preparation

    func testPrepareDownscalesLongestEdgeAndKeepsAspectRatio() async throws {
        let source = try XCTUnwrap(Self.pngData(width: 3_000, height: 1_500))

        let prepared = try await PossessionPhotoService.prepare(source)

        let original = try XCTUnwrap(Self.pixelSize(of: prepared.original))
        XCTAssertEqual(original.width, PossessionPhotoService.maxPixelSize)
        XCTAssertEqual(original.height, PossessionPhotoService.maxPixelSize / 2)
    }

    func testPrepareRejectsNonImageData() async {
        do {
            _ = try await PossessionPhotoService.prepare(Data("not an image".utf8))
            XCTFail("Expected unreadableImage")
        } catch {
            XCTAssertEqual(error as? PossessionPhotoService.PhotoError, .unreadableImage)
        }
    }

    // MARK: - Helpers

    private static func pngData(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 3, y: height / 4, width: width / 3, height: height / 2))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }
}
