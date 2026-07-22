import Foundation
import Testing
@testable import Camerae

struct CameraeLocalizationTests {
    @Test func releaseLocalesAreExplicitAndStable() {
        #expect(CameraeLocalization.supportedLocaleIdentifiers == [
            "pt-BR",
            "es",
            "en",
            "fr",
            "de",
            "ru"
        ])
        #expect(CameraeLocalization.developmentLocaleIdentifier == "pt-BR")
    }

    @Test func initialCatalogIsCompleteForEveryReleaseLocale() throws {
        let catalog = try LocalizationCatalog.load(named: "Localizable")
        #expect(catalog.sourceLanguage == CameraeLocalization.developmentLocaleIdentifier)

        for (key, entry) in catalog.strings {
            for locale in CameraeLocalization.supportedLocaleIdentifiers {
                let value = entry.localizations?[locale]?.stringUnit?.value
                #expect(value?.isEmpty == false, "\(key) is missing \(locale)")
            }
        }
    }

    @Test func privacyCatalogCoversEveryPermissionAndReleaseLocale() throws {
        let catalog = try LocalizationCatalog.load(named: "InfoPlist")
        let permissionKeys = [
            "NSCameraUsageDescription",
            "NSLocationWhenInUseUsageDescription",
            "NSLocationTemporaryUsageDescriptionDictionary.RepeatableAlignment"
        ]

        for key in permissionKeys {
            let entry = try #require(catalog.strings[key])
            for locale in CameraeLocalization.supportedLocaleIdentifiers {
                let value = entry.localizations?[locale]?.stringUnit?.value
                #expect(value?.isEmpty == false, "\(key) is missing \(locale)")
            }
        }
    }

    @Test func automationIdentifiersDoNotDependOnTranslatedCopy() {
        #expect(CameraeAccessibility.openModule(.repeatable) == "camerae.module.repeatable.open")
        #expect(CameraeAccessibility.newProject(.astrophotography) == "camerae.project.astrophotography.new")
        #expect(CameraeAccessibility.createProject == "camerae.project.create")
    }
}

private struct LocalizationCatalog: Decodable {
    struct Entry: Decodable {
        struct Localization: Decodable {
            struct StringUnit: Decodable {
                let value: String
            }

            let stringUnit: StringUnit?
        }

        let localizations: [String: Localization]?
    }

    let sourceLanguage: String
    let strings: [String: Entry]

    static func load(named name: String) throws -> Self {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalogURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Camerae/\(name).xcstrings")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: catalogURL))
    }
}
