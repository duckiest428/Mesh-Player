//
//  LyricsTranslation.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Experimental: translates lyrics into your language with Apple's on-device Translation
//  framework (macOS 15 / iOS 18 and later). Lyrics already in your language are left alone.
//

import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum ExperimentalSettings {
    static let wordLyricsKey = "experimental.wordLyrics"
    static let translateLyricsKey = "experimental.translateLyrics"
}

extension View {
    /// Fills `translations` (line id → translated text) when enabled and the lyrics are in
    /// another language than the system's.
    func lyricsTranslation(_ lines: [SyncedLyricLine], enabled: Bool, into translations: Binding<[UUID: String]>) -> some View {
        modifier(LyricsTranslationModifier(lines: lines, enabled: enabled, translations: translations))
    }
}

private struct LyricsTranslationModifier: ViewModifier {
    let lines: [SyncedLyricLine]
    let enabled: Bool
    @Binding var translations: [UUID: String]

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, iOS 18.0, *) {
            content.modifier(SystemTranslation(lines: lines, enabled: enabled, translations: $translations))
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
    @Binding var translations: [UUID: String]
    @State private var configuration: TranslationSession.Configuration?

    private var textLines: [SyncedLyricLine] { lines.filter { !$0.isBreak && $0.text != "♫" } }
    private var signature: String { "\(enabled)|" + (lines.first?.id.uuidString ?? "") + "|\(lines.count)" }

    func body(content: Content) -> some View {
        content
            .task(id: signature) {
                translations = [:]
                configuration = nil
                guard enabled, let source = Self.language(of: textLines.map(\.text).joined(separator: "\n")) else { return }
                let mine = Locale.current.language.languageCode?.identifier
                guard source.languageCode?.identifier != mine else { return }
                configuration = TranslationSession.Configuration(source: source, target: nil)
            }
            .translationTask(configuration) { session in
                let requests = textLines.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString) }
                guard !requests.isEmpty, let responses = try? await session.translations(from: requests) else { return }
                var result: [UUID: String] = [:]
                for response in responses {
                    guard let idString = response.clientIdentifier, let id = UUID(uuidString: idString) else { continue }
                    let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty && text.caseInsensitiveCompare(response.sourceText) != .orderedSame { result[id] = text }
                }
                await MainActor.run { translations = result }
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
