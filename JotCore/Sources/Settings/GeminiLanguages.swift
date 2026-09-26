// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

public struct GeminiLanguage: Identifiable, Hashable, Sendable {
    public let name: String
    public let code: String

    public var id: String { code }

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}

/// Languages the Gemini Live API can understand and speak, used as translation
/// targets. Source: https://ai.google.dev/gemini-api/docs/live-api/capabilities
/// ("Supported languages", 99 entries, fetched 2026-09-26).
public enum GeminiLanguages {
    public static let supported: [GeminiLanguage] = [
        .init(name: "Afrikaans", code: "af"), .init(name: "Akan", code: "ak"),
        .init(name: "Albanian", code: "sq"), .init(name: "Amharic", code: "am"),
        .init(name: "Arabic", code: "ar"), .init(name: "Armenian", code: "hy"),
        .init(name: "Assamese", code: "as"), .init(name: "Azerbaijani", code: "az"),
        .init(name: "Basque", code: "eu"), .init(name: "Belarusian", code: "be"),
        .init(name: "Bengali", code: "bn"), .init(name: "Bosnian", code: "bs"),
        .init(name: "Bulgarian", code: "bg"), .init(name: "Burmese", code: "my"),
        .init(name: "Catalan", code: "ca"), .init(name: "Cebuano", code: "ceb"),
        .init(name: "Chinese (Simplified)", code: "zh-Hans"),
        .init(name: "Chinese (Traditional)", code: "zh-Hant"),
        .init(name: "Croatian", code: "hr"), .init(name: "Czech", code: "cs"),
        .init(name: "Danish", code: "da"), .init(name: "Dutch", code: "nl"),
        .init(name: "English", code: "en"), .init(name: "Estonian", code: "et"),
        .init(name: "Faroese", code: "fo"), .init(name: "Filipino", code: "fil"),
        .init(name: "Finnish", code: "fi"), .init(name: "French", code: "fr"),
        .init(name: "Galician", code: "gl"), .init(name: "Georgian", code: "ka"),
        .init(name: "German", code: "de"), .init(name: "Greek", code: "el"),
        .init(name: "Gujarati", code: "gu"), .init(name: "Hausa", code: "ha"),
        .init(name: "Hebrew", code: "he"), .init(name: "Hindi", code: "hi"),
        .init(name: "Hungarian", code: "hu"), .init(name: "Icelandic", code: "is"),
        .init(name: "Indonesian", code: "id"), .init(name: "Irish", code: "ga"),
        .init(name: "Italian", code: "it"), .init(name: "Japanese", code: "ja"),
        .init(name: "Kannada", code: "kn"), .init(name: "Kazakh", code: "kk"),
        .init(name: "Khmer", code: "km"), .init(name: "Kinyarwanda", code: "rw"),
        .init(name: "Korean", code: "ko"), .init(name: "Kurdish", code: "ku"),
        .init(name: "Kyrgyz", code: "ky"), .init(name: "Lao", code: "lo"),
        .init(name: "Latvian", code: "lv"), .init(name: "Lithuanian", code: "lt"),
        .init(name: "Macedonian", code: "mk"), .init(name: "Malay", code: "ms"),
        .init(name: "Malayalam", code: "ml"), .init(name: "Maltese", code: "mt"),
        .init(name: "Maori", code: "mi"), .init(name: "Marathi", code: "mr"),
        .init(name: "Mongolian", code: "mn"), .init(name: "Nepali", code: "ne"),
        .init(name: "Norwegian", code: "no"), .init(name: "Odia", code: "or"),
        .init(name: "Oromo", code: "om"), .init(name: "Pashto", code: "ps"),
        .init(name: "Persian", code: "fa"), .init(name: "Polish", code: "pl"),
        .init(name: "Portuguese (Brazil)", code: "pt-BR"),
        .init(name: "Portuguese (Portugal)", code: "pt-PT"),
        .init(name: "Punjabi", code: "pa"), .init(name: "Quechua", code: "qu"),
        .init(name: "Romanian", code: "ro"), .init(name: "Romansh", code: "rm"),
        .init(name: "Russian", code: "ru"), .init(name: "Serbian", code: "sr"),
        .init(name: "Sindhi", code: "sd"), .init(name: "Sinhala", code: "si"),
        .init(name: "Slovak", code: "sk"), .init(name: "Slovenian", code: "sl"),
        .init(name: "Somali", code: "so"), .init(name: "Southern Sotho", code: "st"),
        .init(name: "Spanish", code: "es"), .init(name: "Swahili", code: "sw"),
        .init(name: "Swedish", code: "sv"), .init(name: "Tajik", code: "tg"),
        .init(name: "Tamil", code: "ta"), .init(name: "Telugu", code: "te"),
        .init(name: "Thai", code: "th"), .init(name: "Tswana", code: "tn"),
        .init(name: "Turkish", code: "tr"), .init(name: "Turkmen", code: "tk"),
        .init(name: "Ukrainian", code: "uk"), .init(name: "Urdu", code: "ur"),
        .init(name: "Uzbek", code: "uz"), .init(name: "Vietnamese", code: "vi"),
        .init(name: "Welsh", code: "cy"), .init(name: "Western Frisian", code: "fy"),
        .init(name: "Wolof", code: "wo"), .init(name: "Yoruba", code: "yo"),
        .init(name: "Zulu", code: "zu")
    ]
}
