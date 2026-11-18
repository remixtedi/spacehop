import Cocoa

// spacehop: instant macOS Space switching.
//
//   spacehop            run the background daemon (Ctrl+Left/Right, 3-finger swipe)
//   spacehop left       switch one Space left and exit
//   spacehop right      switch one Space right and exit
//   spacehop setup      turn off the system animated Ctrl+arrow shortcuts
//   spacehop teardown   turn them back on
//   spacehop version    print the version

let usage = "usage: spacehop [left | right | setup | teardown | version]\n"

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "left", "right":
    switchSpace(right: args[1] == "right")
    // Let the posted events flush before exit.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    exit(0)
case "setup":
    setCtrlArrowShortcuts(enabled: false)
    print("spacehop setup: system animated Ctrl+arrow shortcuts turned off (now and after login).")
    exit(0)
case "teardown":
    setCtrlArrowShortcuts(enabled: true)
    print("spacehop teardown: system Ctrl+arrow shortcuts turned back on.")
    exit(0)
case "version", "--version":
    print("spacehop \(spacehopVersion)")
    exit(0)
case "":
    runDaemon()
default:
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(1)
}
