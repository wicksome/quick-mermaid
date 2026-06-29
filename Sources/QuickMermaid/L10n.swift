import Foundation

/// Native UI localization. Uses "ko" when the system language is Korean, otherwise falls back to "en".
enum L10n {
    /// Resolved UI language ("en"/"ko"); honors the Settings preference (default: system).
    static var lang: String { Settings.resolvedLanguage }

    private static let table: [String: [String: String]] = [
        "menu.settings":     ["ko": "설정…",                          "en": "Settings…"],
        "menu.quit":         ["ko": "종료",                           "en": "Quit"],
        "menu.updateAvailable": ["ko": "업데이트 있음",               "en": "Update available"],
        "settings.secGeneral": ["ko": "일반",                         "en": "General"],
        "settings.secAppearance": ["ko": "모양",                      "en": "Appearance"],
        "settings.secShortcut": ["ko": "단축키",                      "en": "Shortcut"],
        "settings.secAbout": ["ko": "정보",                           "en": "About"],
        "settings.launchAtLogin": ["ko": "로그인 시 자동 실행",         "en": "Launch at login"],
        "settings.upToDate": ["ko": "최신 버전입니다",                 "en": "You're up to date"],
        "settings.updateAvailable": ["ko": "업데이트 있음",            "en": "Update available"],
        "settings.title":    ["ko": "QuickMermaid 설정",              "en": "QuickMermaid Settings"],
        "settings.language": ["ko": "언어",                           "en": "Language"],
        "settings.langSystem":["ko": "시스템",                        "en": "System"],
        "settings.theme":    ["ko": "기본 테마",                      "en": "Default theme"],
        "settings.zoom":     ["ko": "기본 확대율 (%)",                "en": "Default zoom (%)"],
        "settings.bg":       ["ko": "배경색",                         "en": "Background"],
        "settings.font":     ["ko": "글꼴",                           "en": "Font"],
        "settings.fontDefault":["ko": "기본",                        "en": "Default"],
        "settings.shortcut": ["ko": "단축키로 선택 영역 다이어그램 보기", "en": "Render selection via shortcut"],
        "settings.keepOpen": ["ko": "포커스를 잃어도 창을 닫지 않기",     "en": "Keep window open when focus is lost"],
        "settings.version":  ["ko": "버전",                           "en": "Version"],
        "settings.openReleases": ["ko": "릴리스 열기",                 "en": "Open Releases"],
        "settings.preview":  ["ko": "미리보기",                       "en": "Preview"],
        "settings.recording":["ko": "키 입력…",                       "en": "Type shortcut…"],
    ]

    static func t(_ key: String) -> String {
        table[key]?[lang] ?? table[key]?["en"] ?? key
    }
}
