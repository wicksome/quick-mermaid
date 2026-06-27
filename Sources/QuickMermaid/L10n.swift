import Foundation

/// Native UI localization. Uses "ko" when the system language is Korean, otherwise falls back to "en".
enum L10n {
    static let lang: String = {
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("ko") ? "ko" : "en"
    }()

    private static let table: [String: [String: String]] = [
        "menu.settings":     ["ko": "설정…",                          "en": "Settings…"],
        "menu.quit":         ["ko": "종료",                           "en": "Quit"],
        "settings.title":    ["ko": "QuickMermaid 설정",              "en": "QuickMermaid Settings"],
        "settings.theme":    ["ko": "기본 테마",                      "en": "Default theme"],
        "settings.zoom":     ["ko": "기본 확대율 (%)",                "en": "Default zoom (%)"],
        "settings.bg":       ["ko": "배경색",                         "en": "Background"],
        "settings.shortcut": ["ko": "단축키로 선택 영역 다이어그램 보기", "en": "Render selection via shortcut"],
        "settings.keepOpen": ["ko": "포커스를 잃어도 창을 닫지 않기",     "en": "Keep window open when focus is lost"],
        "settings.preview":  ["ko": "미리보기",                       "en": "Preview"],
        "settings.recording":["ko": "키 입력…",                       "en": "Type shortcut…"],
    ]

    static func t(_ key: String) -> String {
        table[key]?[lang] ?? table[key]?["en"] ?? key
    }
}
