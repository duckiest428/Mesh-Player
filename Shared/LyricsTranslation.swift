//
//  LyricsTranslation.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Translates lyrics with Apple's on-device Translation framework (macOS 15 / iOS 18 and
//  later), into the language picked in Settings or the lyrics view (your system language by
//  default). Lyrics already in that language are left alone.
//

import Combine
import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum ExperimentalSettings {
    static let wordLyricsKey = "experimental.wordLyrics"
}

enum LyricsSettings {
    static let translateKey = "lyrics.translate"
    /// A language identifier such as "es" or "zh-Hans"; empty means the system language.
    static let translationLanguageKey = "lyrics.translationLanguage"

    static var isTranslationAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }

    /// The language lyrics get translated into.
    static func targetLanguage(_ stored: String) -> Locale.Language {
        stored.isEmpty ? Locale.current.language : Locale.Language(identifier: stored)
    }

    static func displayName(_ identifier: String) -> String {
        let id = identifier.isEmpty ? (Locale.current.language.languageCode?.identifier ?? "en") : identifier
        return Locale.current.localizedString(forIdentifier: id)?.capitalized(with: Locale.current) ?? id
    }
}

/// The languages Apple's translation can translate lyrics into.
@MainActor
final class TranslationLanguages: ObservableObject {
    static let shared = TranslationLanguages()

    /// Identifiers sorted by their name in your language, without the system language (offered
    /// separately as the default).
    @Published private(set) var identifiers: [String] = []
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        #if canImport(Translation)
        if #available(macOS 15.0, iOS 18.0, *) {
            Task {
                let languages = await LanguageAvailability().supportedLanguages
                var seen = Set<String>()
                let mine = Locale.current.language.minimalIdentifier
                identifiers = languages.map(\.minimalIdentifier)
                    .filter { $0 != mine && seen.insert($0).inserted }
                    .sorted { LyricsSettings.displayName($0).localizedCompare(LyricsSettings.displayName($1)) == .orderedAscending }
            }
        }
        #endif
    }
}

/// Where the current song's translation is at, for the lyrics view's translate button.
enum LyricsTranslationStatus: Equatable {
    case off, translating, translated, alreadyInLanguage, failed
}

/// The current lyrics' translations, worked out once for every lyrics view.
@MainActor
final class LyricsTranslator: ObservableObject {
    static let shared = LyricsTranslator()
    /// Line id → the line in the chosen language.
    @Published fileprivate(set) var translations: [UUID: String] = [:]
    @Published fileprivate(set) var status: LyricsTranslationStatus = .off
}

extension View {
    /// Translates `lines` into `LyricsTranslator.shared` when enabled and the lyrics are in
    /// another language than `target`. Attach it once, to a view that's always on screen.
    func lyricsTranslation(_ lines: [SyncedLyricLine], enabled: Bool, target: String) -> some View {
        modifier(LyricsTranslationModifier(lines: lines, enabled: enabled, target: target))
    }
}

private struct LyricsTranslationModifier: ViewModifier {
    let lines: [SyncedLyricLine]
    let enabled: Bool
    let target: String

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, iOS 18.0, *) {
            content.modifier(SystemTranslation(lines: lines, enabled: enabled, target: target))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
@available(macOS 15.0, iOS 18.0, *)
private struct SystemTranslation: ViewModifier {
    let lines: [SyncedLyricLine]
    let enabled: Bool
    let target: String
    @State private var configuration: TranslationSession.Configuration?
    private var store: LyricsTranslator { LyricsTranslator.shared }

    private var textLines: [SyncedLyricLine] { lines.filter { !$0.isBreak && $0.text != "♫" } }
    private var signature: String { "\(enabled)|\(target)|" + (lines.first?.id.uuidString ?? "") + "|\(lines.count)" }

    func body(content: Content) -> some View {
        content
            .task(id: signature) {
                store.translations = [:]
                configuration = nil
                guard enabled else { store.status = .off; return }
                guard let source = Self.language(of: textLines.map(\.text).joined(separator: "\n")) else { store.status = .failed; return }
                let targetLanguage = LyricsSettings.targetLanguage(target)
                guard source.languageCode?.identifier != targetLanguage.languageCode?.identifier else {
                    store.status = .alreadyInLanguage
                    return
                }
                store.status = .translating
                configuration = TranslationSession.Configuration(source: source, target: targetLanguage)
            }
            .translationTask(configuration) { session in
                let requests = textLines.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString) }
                guard !requests.isEmpty else { return }
                do {
                    // Asks to download the languages first if they aren't on this device yet.
                    try await session.prepareTranslation()
                    let responses = try await session.translations(from: requests)
                    var result: [UUID: String] = [:]
                    for response in responses {
                        guard let idString = response.clientIdentifier, let id = UUID(uuidString: idString) else { continue }
                        let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty && text.caseInsensitiveCompare(response.sourceText) != .orderedSame { result[id] = text }
                    }
                    await MainActor.run {
                        store.translations = result
                        store.status = .translated
                    }
                } catch {
                    await MainActor.run { store.status = .failed }
                }
            }
    }

    private static func language(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}
#endif
