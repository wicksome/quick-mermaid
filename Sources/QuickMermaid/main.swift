import AppKit

/// Execution mode. Determined by command-line arguments.
enum AppMode {
    case service          // default: menu bar resident + Services handler
    case cli(String)      // --stdin: render mermaid received via pipe once and exit
    case settings         // --settings: show settings window and exit when closed
    case selfTest         // --selftest: verify offscreen render and exit
    case test             // --test: run the renderer JS test suite offscreen and exit
}

let args = CommandLine.arguments

// --encode: read source from stdin, print a quickmermaid:// link, exit.
// Pure text transform — no GUI, so it runs before NSApplication is created.
if args.contains("--encode") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let url = URLScheme.encode(text: text) else {
        exit(1)
    }
    print(url.absoluteString)
    exit(0)
}

let mode: AppMode
if args.contains("--test") {
    mode = .test
} else if args.contains("--selftest") {
    mode = .selfTest
} else if args.contains("--settings") {
    mode = .settings
} else if args.contains("--stdin") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    mode = .cli(String(data: data, encoding: .utf8) ?? "")
} else {
    mode = .service
}

let app = NSApplication.shared
let delegate = AppDelegate(mode: mode)
app.delegate = delegate
// The settings window must behave like a regular window for natural focus/front-display. Others are menu-bar-only (.accessory).
switch mode {
case .settings: app.setActivationPolicy(.regular)
default:        app.setActivationPolicy(.accessory)
}
app.run()
