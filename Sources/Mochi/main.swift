import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    Sheet.render(to: args[i + 1], coatID: i + 2 < args.count ? args[i + 2] : nil)
    exit(0)
}

if args.contains("--bench") { Bench.run(); exit(0) }
if let i = args.firstIndex(of: "--showcase"), i + 1 < args.count {
    Showcase.render(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    Icon.render(to: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
