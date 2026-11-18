import Foundation

// Test runner: plain asserts, no framework. Built by `scripts/build.sh --test`.

var failures = 0

func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL \(file):\(line): \(message)")
    }
}

let tests: [(String, () -> Void)] = [
    ("test_fixed1616", test_fixed1616),
    ("test_payload_layout", test_payload_layout),
    ("test_augment_header", test_augment_header),
    ("test_postedSign_naturalOff", test_postedSign_naturalOff),
    ("test_clamp_and_prediction", test_clamp_and_prediction),
]

for (name, run) in tests {
    let before = failures
    run()
    print(failures == before ? "ok   \(name)" : "FAIL \(name)")
}
print(failures == 0 ? "all tests passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
