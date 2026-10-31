import AppKit

public enum SaveTests {
    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diffr-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Load → save round-trips bytes exactly (BOM, CRLF, UTF-16, Windows-1252)") {
            let dir = try tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let samples: [(String, [UInt8])] = [
                ("utf8-bom-crlf", [0xEF, 0xBB, 0xBF] + Array("a\r\nb\r\n".utf8)),
                ("utf16le", [0xFF, 0xFE, 0x68, 0x00, 0xE9, 0x00, 0x0A, 0x00]),
                ("utf16be", [0xFE, 0xFF, 0x00, 0x68, 0x00, 0xE9]),
                ("cp1252", [0x63, 0x61, 0x66, 0xE9, 0x20, 0x80]) // "café €"
            ]
            for (name, bytes) in samples {
                let url = dir.appendingPathComponent(name)
                try Data(bytes).write(to: url)
                let loaded = try TextFileLoader.loadFile(url: url)
                try TextFileLoader.save(loaded.text, to: url, encoding: loaded.encoding)
                let written = try [UInt8](Data(contentsOf: url))
                try expect(written == bytes, "\(name): \(written) != \(bytes)")
            }
        }

        testRunner("Saving text the original encoding cannot represent fails instead of losing characters") {
            var failure: TextFileLoadError?
            do { _ = try TextFileLoader.encode("emoji 😀", as: .isoLatin1) } catch let e as TextFileLoadError { failure = e }
            try expect(failure == .unencodable(encodingName: "ISO Latin-1"))
        }

        testRunner("Saving through a symlink updates the target, keeps the link and the permissions") {
            let dir = try tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let target = dir.appendingPathComponent("real.txt")
            let link = dir.appendingPathComponent("link.txt")
            try "old".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            try TextFileLoader.save("new", to: link, encoding: .utf8)

            try expect(try String(contentsOf: target, encoding: .utf8) == "new")
            let linkType = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
            try expect(linkType == .typeSymbolicLink, "Symlink must survive the save")
            let perms = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
            try expect(perms == 0o600, "Permissions must be preserved, got \(String(describing: perms))")
        }

        testRunner("PaneDocument tracks dirtiness exactly and notices external modification") {
            let dir = try tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("doc.txt")
            try "hello".write(to: url, atomically: true, encoding: .utf8)
            let doc = PaneDocument(loaded: try TextFileLoader.loadFile(url: url))
            try expect(!doc.isDirty(currentText: "hello"))
            try expect(doc.isDirty(currentText: "hello!"))
            try expect(doc.isDirty(currentText: "he\u{301}llo") == true)
            try expect(!doc.hasChangedOnDisk)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
            try expect(doc.hasChangedOnDisk, "External change must be detected")
        }

        testRunner("Window controller: open → edit marks dirty → save writes file and clears dirty") {
            let dir = try tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("left.txt")
            try "one\ntwo\n".write(to: url, atomically: true, encoding: .utf8)

            let controller = MainWindowController()
            controller.loadFile(at: url, into: .left)
            try expect(controller.documents[.left]?.url == url)
            try expect(!controller.hasUnsavedChanges)
            try expect(controller.leftTitleLabel.stringValue == "left.txt")

            let editor = controller.containerView.leftEditor
            editor.textView.insertText("zero\n", replacementRange: NSRange(location: 0, length: 0))
            controller.refreshDocumentState()
            try expect(controller.hasUnsavedChanges)
            try expect(controller.leftTitleLabel.stringValue.hasSuffix("— Edited"))
            try expect(controller.window?.isDocumentEdited == true)

            var saved = false
            controller.save(side: .left, chooseLocation: false) { saved = $0 }
            try expect(saved, "Save should complete without prompting")
            try expect(try String(contentsOf: url, encoding: .utf8) == "zero\none\ntwo\n")
            try expect(!controller.hasUnsavedChanges)
            try expect(controller.window?.isDocumentEdited == false)
            try expect(controller.windowShouldClose(controller.window!), "Clean window closes without asking")
            controller.window?.close()
        }

        testRunner("Pasted scratch text without a file never blocks closing") {
            let controller = MainWindowController()
            controller.diffCoordinator.setInitialTexts(left: "scratch", right: "pad")
            try expect(!controller.hasUnsavedChanges)
            try expect(controller.windowShouldClose(controller.window!))
            controller.window?.close()
        }
    }
}
