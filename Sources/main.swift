import Cocoa

// spacehop: instant macOS Space switching.
//
//   spacehop            run the background daemon (Ctrl+Left/Right, 3-finger swipe)
//   spacehop left       switch one Space left and exit
//   spacehop right      switch one Space right and exit
//   spacehop version    print the version

let spacehopVersion = "0.1.0"
let usage = "usage: spacehop [left | right | version]\n"

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "left", "right":
    switchSpace(right: args[1] == "right")
    // Let the posted events flush before exit.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    exit(0)
case "version", "--version":
    print("spacehop \(spacehopVersion)")
    exit(0)
default:
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(1)
}
