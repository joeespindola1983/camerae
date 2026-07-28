import Foundation
import Testing
@testable import Camerae

@Suite("Astro photo feature")
struct AstroPhotoFeatureTests {
    @Test("Astro photo offers the approved stacking counts and defaults to ten")
    func stackCountOptions() {
        #expect(AstroPhotoStackCount.allCases.map(\.rawValue) == [5, 10, 20, 30])
        #expect(AstroPhotoStackCount.defaultValue == .ten)
        #expect(AstroPhotoStackCount.nearest(to: 7) == .five)
        #expect(AstroPhotoStackCount.nearest(to: 26) == .thirty)
    }

    @Test("Astro photo defaults preserve editable originals")
    func defaultSettings() {
        let settings = AstroPhotoCaptureSettings.default

        #expect(settings.stackCount == .ten)
        #expect(settings.sourceFormat == .dng)
        #expect(settings.preservesOriginals)
    }

    @Test("Celestial layers require a trusted plate solution")
    func layerAvailability() {
        let trusted = CelestialPlateSolution(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            fieldWidthDegrees: 64,
            rotationDegrees: 3,
            confidence: 0.92
        )
        let uncertain = CelestialPlateSolution(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            fieldWidthDegrees: 64,
            rotationDegrees: 3,
            confidence: 0.42
        )

        #expect(
            CelestialLayerAvailability.availableLayers(
                solution: trusted,
                hasCaptureDate: true,
                hasLocation: true
            ) == Set(CelestialLayerKind.allCases)
        )
        #expect(
            CelestialLayerAvailability.availableLayers(
                solution: trusted,
                hasCaptureDate: false,
                hasLocation: true
            ) == [.nebulae, .galaxies]
        )
        #expect(
            CelestialLayerAvailability.availableLayers(
                solution: uncertain,
                hasCaptureDate: true,
                hasLocation: true
            ).isEmpty
        )
    }

    @Test("Annotation documents round trip without losing layer choices")
    func annotationDocumentRoundTrip() throws {
        let solution = CelestialPlateSolution(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            fieldWidthDegrees: 64,
            rotationDegrees: 3,
            confidence: 0.92
        )
        let document = CelestialAnnotationDocument(
            sourceAssetIdentifier: "astro-result.dng",
            plateSolution: solution,
            enabledLayers: [.planets, .nebulae],
            annotations: [
                CelestialAnnotation(
                    identifier: "planet.jupiter",
                    kind: .planets,
                    displayName: "Júpiter",
                    normalizedX: 0.42,
                    normalizedY: 0.18,
                    confidence: 0.95
                )
            ]
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(CelestialAnnotationDocument.self, from: data)

        #expect(decoded == document)
        #expect(decoded.version == CelestialAnnotationDocument.currentVersion)
    }

    @Test("Projection places the plate center at the center of the photo")
    func plateCenterProjection() {
        let solution = CelestialPlateSolution(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            fieldWidthDegrees: 60,
            rotationDegrees: 0,
            confidence: 0.95
        )

        let point = CelestialProjection.normalizedPoint(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            solution: solution,
            imageAspectRatio: 4.0 / 3.0
        )

        #expect(point != nil)
        #expect(abs((point?.x ?? 0) - 0.5) < 0.000_1)
        #expect(abs((point?.y ?? 0) - 0.5) < 0.000_1)
    }

    @Test("Annotation engine filters objects outside the solved field")
    func annotationFieldFiltering() {
        let solution = CelestialPlateSolution(
            rightAscensionDegrees: 266.4,
            declinationDegrees: -29,
            fieldWidthDegrees: 30,
            rotationDegrees: 0,
            confidence: 0.95
        )
        let objects = [
            CelestialCatalogObject(
                identifier: "center",
                kind: .nebulae,
                displayName: "Centro",
                rightAscensionDegrees: 266.4,
                declinationDegrees: -29
            ),
            CelestialCatalogObject(
                identifier: "far",
                kind: .galaxies,
                displayName: "Distante",
                rightAscensionDegrees: 10,
                declinationDegrees: 50
            )
        ]

        let annotations = CelestialAnnotationEngine.annotations(
            objects: objects,
            solution: solution,
            enabledLayers: [.nebulae, .galaxies],
            imageAspectRatio: 4.0 / 3.0
        )

        #expect(annotations.map(\.identifier) == ["center"])
    }

    @Test("Offline planetary ephemeris produces valid equatorial coordinates")
    func planetaryEphemeris() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-07-27T00:00:00Z")
        )
        let planets = CelestialSolarSystemCatalog.objects(at: date)

        #expect(planets.count == 7)
        #expect(planets.allSatisfy { (0..<360).contains($0.rightAscensionDegrees) })
        #expect(planets.allSatisfy { (-90...90).contains($0.declinationDegrees) })
        #expect(planets.allSatisfy { $0.kind == .planets })
    }
}
