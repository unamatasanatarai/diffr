import Cocoa

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let location: String
    var description: String { return "\(message) (\(location))" }
}

/// Throwing assertion: a failure is reported and the suite continues (unlike `assert`, which traps).
func expect(_ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "Expectation failed",
            file: StaticString = #fileID, line: UInt = #line) throws {
    if try !condition() {
        throw TestFailure(message: message(), location: "\(file):\(line)")
    }
}

@main
struct TestMain {
    static func main() {
        // Initialize NSApplication for AppKit UI components
        _ = NSApplication.shared

        print("==================================================")
        print("         Running Swift Native Test Suite          ")
        print("==================================================")

        var passed = 0
        var failed = 0
        let totalStart = CFAbsoluteTimeGetCurrent()

        let runTest: (String, () throws -> Void) -> Void = { name, block in
            let start = CFAbsoluteTimeGetCurrent()
            do {
                try block()
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                print(String(format: "  ✔ PASS: %@ (%.2fms)", name, elapsedMs))
                passed += 1
            } catch {
                print("  ❌ FAIL: \(name) - \(error)")
                failed += 1
            }
        }

        print("\n--- Application Configuration & State Suite ---")
        AppTests.run(testRunner: runTest)

        print("\n--- Diff Engine & Alignment Suite ---")
        DiffEngineTests.run(testRunner: runTest)

        print("\n--- Word-Level Difference Suite ---")
        WordDiffTests.run(testRunner: runTest)

        print("\n--- Hunk Merge & Copy Suite ---")
        HunkCopyTests.run(testRunner: runTest)

        print("\n--- Adversarial Regression Suite ---")
        RegressionTests.run(testRunner: runTest)

        print("\n--- File Save & Unsaved Changes Suite ---")
        SaveTests.run(testRunner: runTest)

        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0

        print("\n--------------------------------------------------")
        print(String(format: "  Summary: %d Passed | %d Failed (Total: %.2fms)", passed, failed, totalElapsedMs))
        print("==================================================")

        if failed > 0 {
            exit(1)
        }
    }
}
