import CameraeCore
import CameraeVision
import CoreGraphics
import Foundation

enum AstroPhotoStackCount: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case five = 5
    case ten = 10
    case twenty = 20
    case thirty = 30

    static let defaultValue = Self.ten

    var id: Int { rawValue }

    var isRecommended: Bool {
        self == .ten
    }

    var requiresStableDarkScene: Bool {
        self == .twenty || self == .thirty
    }

    static func nearest(to value: Int) -> Self {
        allCases.min {
            abs($0.rawValue - value) < abs($1.rawValue - value)
        } ?? defaultValue
    }
}

struct AstroPhotoCaptureSettings: Codable, Equatable, Sendable {
    var stackCount: AstroPhotoStackCount
    var sourceFormat: CaptureSourceFormat
    var preservesOriginals: Bool

    static let `default` = Self(
        stackCount: .defaultValue,
        sourceFormat: .dng,
        preservesOriginals: true
    )
}

enum CelestialLayerKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case planets
    case nebulae
    case galaxies

    var id: String { rawValue }
}

struct CelestialPlateSolution: Codable, Equatable, Sendable {
    var rightAscensionDegrees: Double
    var declinationDegrees: Double
    var fieldWidthDegrees: Double
    var rotationDegrees: Double
    var confidence: Double
    var parityInverted = false

    var isTrusted: Bool {
        confidence >= 0.8
            && (0...360).contains(rightAscensionDegrees)
            && (-90...90).contains(declinationDegrees)
            && fieldWidthDegrees > 0
    }
}

struct CelestialCatalogObject: Codable, Equatable, Sendable {
    var identifier: String
    var kind: CelestialLayerKind
    var displayName: String
    var rightAscensionDegrees: Double
    var declinationDegrees: Double
}

struct CelestialAnnotation: Codable, Equatable, Identifiable, Sendable {
    var identifier: String
    var kind: CelestialLayerKind
    var displayName: String
    var normalizedX: Double
    var normalizedY: Double
    var confidence: Double

    var id: String { identifier }
}

struct CelestialAnnotationDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var sourceAssetIdentifier: String
    var plateSolution: CelestialPlateSolution
    var enabledLayers: Set<CelestialLayerKind>
    var annotations: [CelestialAnnotation]

    init(
        version: Int = currentVersion,
        sourceAssetIdentifier: String,
        plateSolution: CelestialPlateSolution,
        enabledLayers: Set<CelestialLayerKind>,
        annotations: [CelestialAnnotation]
    ) {
        self.version = version
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.plateSolution = plateSolution
        self.enabledLayers = enabledLayers
        self.annotations = annotations
    }
}

enum CelestialLayerAvailability {
    static func availableLayers(
        solution: CelestialPlateSolution,
        hasCaptureDate: Bool,
        hasLocation: Bool
    ) -> Set<CelestialLayerKind> {
        guard solution.isTrusted else { return [] }

        var layers: Set<CelestialLayerKind> = [.nebulae, .galaxies]
        if hasCaptureDate, hasLocation {
            layers.insert(.planets)
        }
        return layers
    }
}

enum CelestialProjection {
    static func normalizedPoint(
        rightAscensionDegrees: Double,
        declinationDegrees: Double,
        solution: CelestialPlateSolution,
        imageAspectRatio: Double
    ) -> CGPoint? {
        guard solution.isTrusted, imageAspectRatio > 0 else { return nil }

        let ra = rightAscensionDegrees.radians
        let dec = declinationDegrees.radians
        let centerRA = solution.rightAscensionDegrees.radians
        let centerDec = solution.declinationDegrees.radians
        let deltaRA = normalizedRadians(ra - centerRA)
        let denominator = sin(dec) * sin(centerDec)
            + cos(dec) * cos(centerDec) * cos(deltaRA)
        guard denominator > 0 else { return nil }

        var x = cos(dec) * sin(deltaRA) / denominator
        var y = (
            cos(centerDec) * sin(dec)
                - sin(centerDec) * cos(dec) * cos(deltaRA)
        ) / denominator

        let rotation = solution.rotationDegrees.radians
        let rotatedX = x * cos(rotation) - y * sin(rotation)
        let rotatedY = x * sin(rotation) + y * cos(rotation)
        x = solution.parityInverted ? -rotatedX : rotatedX
        y = rotatedY

        let halfWidth = tan((solution.fieldWidthDegrees.radians) / 2)
        guard halfWidth > 0 else { return nil }
        let halfHeight = halfWidth / imageAspectRatio
        let normalizedX = 0.5 + (x / (2 * halfWidth))
        let normalizedY = 0.5 - (y / (2 * halfHeight))
        guard (0...1).contains(normalizedX), (0...1).contains(normalizedY) else {
            return nil
        }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private static func normalizedRadians(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 2 * .pi)
        if result > .pi { result -= 2 * .pi }
        if result < -.pi { result += 2 * .pi }
        return result
    }
}

enum CelestialAnnotationEngine {
    static func annotations(
        objects: [CelestialCatalogObject],
        solution: CelestialPlateSolution,
        enabledLayers: Set<CelestialLayerKind>,
        imageAspectRatio: Double
    ) -> [CelestialAnnotation] {
        objects.compactMap { object in
            guard enabledLayers.contains(object.kind),
                  let point = CelestialProjection.normalizedPoint(
                    rightAscensionDegrees: object.rightAscensionDegrees,
                    declinationDegrees: object.declinationDegrees,
                    solution: solution,
                    imageAspectRatio: imageAspectRatio
                  ) else {
                return nil
            }
            return CelestialAnnotation(
                identifier: object.identifier,
                kind: object.kind,
                displayName: object.displayName,
                normalizedX: point.x,
                normalizedY: point.y,
                confidence: solution.confidence
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

enum CelestialDeepSkyCatalog {
    static let principalObjects: [CelestialCatalogObject] = [
        .init(identifier: "M42", kind: .nebulae, displayName: "Nebulosa de Órion", rightAscensionDegrees: 83.822, declinationDegrees: -5.391),
        .init(identifier: "M8", kind: .nebulae, displayName: "Nebulosa da Lagoa", rightAscensionDegrees: 270.925, declinationDegrees: -24.38),
        .init(identifier: "M20", kind: .nebulae, displayName: "Nebulosa Trífida", rightAscensionDegrees: 270.595, declinationDegrees: -23.03),
        .init(identifier: "NGC3372", kind: .nebulae, displayName: "Nebulosa de Carina", rightAscensionDegrees: 161.265, declinationDegrees: -59.685),
        .init(identifier: "M16", kind: .nebulae, displayName: "Nebulosa da Águia", rightAscensionDegrees: 274.7, declinationDegrees: -13.807),
        .init(identifier: "M17", kind: .nebulae, displayName: "Nebulosa Ômega", rightAscensionDegrees: 275.195, declinationDegrees: -16.172),
        .init(identifier: "M31", kind: .galaxies, displayName: "Galáxia de Andrômeda", rightAscensionDegrees: 10.685, declinationDegrees: 41.269),
        .init(identifier: "M33", kind: .galaxies, displayName: "Galáxia do Triângulo", rightAscensionDegrees: 23.462, declinationDegrees: 30.66),
        .init(identifier: "LMC", kind: .galaxies, displayName: "Grande Nuvem de Magalhães", rightAscensionDegrees: 80.894, declinationDegrees: -69.756),
        .init(identifier: "SMC", kind: .galaxies, displayName: "Pequena Nuvem de Magalhães", rightAscensionDegrees: 13.187, declinationDegrees: -72.829),
        .init(identifier: "M81", kind: .galaxies, displayName: "Galáxia de Bode", rightAscensionDegrees: 148.888, declinationDegrees: 69.065),
        .init(identifier: "C77", kind: .galaxies, displayName: "Centaurus A", rightAscensionDegrees: 201.365, declinationDegrees: -43.019)
    ]
}

enum CelestialSolarSystemCatalog {
    static func objects(at date: Date) -> [CelestialCatalogObject] {
        let days = date.timeIntervalSince(
            Date(timeIntervalSince1970: 946_684_800)
        ) / 86_400
        let earth = heliocentricPosition(for: .earth, days: days)
        let obliquity = (23.4393 - 3.563e-7 * days).radians

        return Planet.allCases.compactMap { planet in
            let heliocentric = heliocentricPosition(for: planet, days: days)
            let geocentricX = heliocentric.x - earth.x
            let geocentricY = heliocentric.y - earth.y
            let geocentricZ = heliocentric.z - earth.z
            let equatorialX = geocentricX
            let equatorialY = geocentricY * cos(obliquity) - geocentricZ * sin(obliquity)
            let equatorialZ = geocentricY * sin(obliquity) + geocentricZ * cos(obliquity)
            let distance = sqrt(
                equatorialX * equatorialX
                    + equatorialY * equatorialY
                    + equatorialZ * equatorialZ
            )
            guard distance > 0 else { return nil }
            let rightAscension = normalizedDegrees(
                atan2(equatorialY, equatorialX).degrees
            )
            let declination = asin(equatorialZ / distance).degrees
            return CelestialCatalogObject(
                identifier: "planet.\(planet.rawValue)",
                kind: .planets,
                displayName: planet.displayName,
                rightAscensionDegrees: rightAscension,
                declinationDegrees: declination
            )
        }
    }

    private enum Planet: String, CaseIterable {
        case mercury
        case venus
        case mars
        case jupiter
        case saturn
        case uranus
        case neptune
        case earth

        static var allCases: [Self] {
            [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]
        }

        var displayName: String {
            switch self {
            case .mercury: "Mercúrio"
            case .venus: "Vênus"
            case .mars: "Marte"
            case .jupiter: "Júpiter"
            case .saturn: "Saturno"
            case .uranus: "Urano"
            case .neptune: "Netuno"
            case .earth: "Terra"
            }
        }
    }

    private struct OrbitalElements {
        let ascendingNode: Double
        let inclination: Double
        let perihelion: Double
        let semiMajorAxis: Double
        let eccentricity: Double
        let meanAnomaly: Double
    }

    private static func heliocentricPosition(
        for planet: Planet,
        days: Double
    ) -> (x: Double, y: Double, z: Double) {
        let elements = orbitalElements(for: planet, days: days)
        let meanAnomaly = normalizedDegrees(elements.meanAnomaly).radians
        var eccentricAnomaly = meanAnomaly
            + elements.eccentricity * sin(meanAnomaly)
                * (1 + elements.eccentricity * cos(meanAnomaly))
        for _ in 0..<8 {
            eccentricAnomaly -= (
                eccentricAnomaly
                    - elements.eccentricity * sin(eccentricAnomaly)
                    - meanAnomaly
            ) / (1 - elements.eccentricity * cos(eccentricAnomaly))
        }
        let xv = elements.semiMajorAxis * (cos(eccentricAnomaly) - elements.eccentricity)
        let yv = elements.semiMajorAxis
            * sqrt(1 - elements.eccentricity * elements.eccentricity)
            * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        let radius = sqrt(xv * xv + yv * yv)
        let node = elements.ascendingNode.radians
        let inclination = elements.inclination.radians
        let longitude = trueAnomaly + elements.perihelion.radians
        return (
            radius * (cos(node) * cos(longitude) - sin(node) * sin(longitude) * cos(inclination)),
            radius * (sin(node) * cos(longitude) + cos(node) * sin(longitude) * cos(inclination)),
            radius * sin(longitude) * sin(inclination)
        )
    }

    private static func orbitalElements(for planet: Planet, days: Double) -> OrbitalElements {
        switch planet {
        case .mercury:
            .init(ascendingNode: 48.3313 + 3.24587e-5 * days, inclination: 7.0047 + 5e-8 * days, perihelion: 29.1241 + 1.01444e-5 * days, semiMajorAxis: 0.387098, eccentricity: 0.205635 + 5.59e-10 * days, meanAnomaly: 168.6562 + 4.0923344368 * days)
        case .venus:
            .init(ascendingNode: 76.6799 + 2.4659e-5 * days, inclination: 3.3946 + 2.75e-8 * days, perihelion: 54.891 + 1.38374e-5 * days, semiMajorAxis: 0.72333, eccentricity: 0.006773 - 1.302e-9 * days, meanAnomaly: 48.0052 + 1.6021302244 * days)
        case .earth:
            .init(ascendingNode: 0, inclination: 0, perihelion: 282.9404 + 4.70935e-5 * days, semiMajorAxis: 1, eccentricity: 0.016709 - 1.151e-9 * days, meanAnomaly: 356.047 + 0.9856002585 * days)
        case .mars:
            .init(ascendingNode: 49.5574 + 2.11081e-5 * days, inclination: 1.8497 - 1.78e-8 * days, perihelion: 286.5016 + 2.92961e-5 * days, semiMajorAxis: 1.523688, eccentricity: 0.093405 + 2.516e-9 * days, meanAnomaly: 18.6021 + 0.5240207766 * days)
        case .jupiter:
            .init(ascendingNode: 100.4542 + 2.76854e-5 * days, inclination: 1.303 - 1.557e-7 * days, perihelion: 273.8777 + 1.64505e-5 * days, semiMajorAxis: 5.20256, eccentricity: 0.048498 + 4.469e-9 * days, meanAnomaly: 19.895 + 0.0830853001 * days)
        case .saturn:
            .init(ascendingNode: 113.6634 + 2.3898e-5 * days, inclination: 2.4886 - 1.081e-7 * days, perihelion: 339.3939 + 2.97661e-5 * days, semiMajorAxis: 9.55475, eccentricity: 0.055546 - 9.499e-9 * days, meanAnomaly: 316.967 + 0.0334442282 * days)
        case .uranus:
            .init(ascendingNode: 74.0005 + 1.3978e-5 * days, inclination: 0.7733 + 1.9e-8 * days, perihelion: 96.6612 + 3.0565e-5 * days, semiMajorAxis: 19.18171 - 1.55e-8 * days, eccentricity: 0.047318 + 7.45e-9 * days, meanAnomaly: 142.5905 + 0.011725806 * days)
        case .neptune:
            .init(ascendingNode: 131.7806 + 3.0173e-5 * days, inclination: 1.77 - 2.55e-7 * days, perihelion: 272.8461 - 6.027e-6 * days, semiMajorAxis: 30.05826 + 3.313e-8 * days, eccentricity: 0.008606 + 2.15e-9 * days, meanAnomaly: 260.2471 + 0.005995147 * days)
        }
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }
}

enum AstroPhotoPlateSolvingError: LocalizedError {
    case catalogUnavailable
    case solutionUnavailable

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "O catálogo offline de estrelas não está disponível."
        case .solutionUnavailable:
            "Não foi possível reconhecer o campo celeste desta foto."
        }
    }
}

struct AstroPhotoPlateSolvingService {
    var catalogURL: URL? = Bundle.main.url(
        forResource: "gaia_dr3_bright_stars",
        withExtension: "camcat"
    )

    func solve(
        imageURL: URL,
        approximateHorizontalFieldOfViewDegrees: Double = 64
    ) throws -> CelestialPlateSolution {
        guard let catalogURL else {
            throw AstroPhotoPlateSolvingError.catalogUnavailable
        }
        let result = try CameraeVisionPlateSolver.solveImage(
            at: imageURL,
            compactCatalogURL: catalogURL,
            approximateHorizontalFieldOfViewDegrees: approximateHorizontalFieldOfViewDegrees,
            minimumMatches: 6
        )
        guard result.status.rawValue == 1, result.confidence >= 0.8 else {
            throw AstroPhotoPlateSolvingError.solutionUnavailable
        }
        return CelestialPlateSolution(
            rightAscensionDegrees: result.rightAscensionDegrees,
            declinationDegrees: result.declinationDegrees,
            fieldWidthDegrees: result.horizontalFieldOfViewDegrees,
            rotationDegrees: result.rollDegrees,
            confidence: result.confidence,
            parityInverted: result.isParityInverted
        )
    }
}

struct CelestialAnnotationStore {
    func load(for imageURL: URL) throws -> CelestialAnnotationDocument? {
        let url = documentURL(for: imageURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            CelestialAnnotationDocument.self,
            from: Data(contentsOf: url)
        )
    }

    func save(_ document: CelestialAnnotationDocument, for imageURL: URL) throws {
        let data = try JSONEncoder().encode(document)
        try data.write(to: documentURL(for: imageURL), options: .atomic)
    }

    private func documentURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("celestial.json")
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
