#!/usr/bin/swift
import Foundation

// 1. Map: https://www.lenovo.com/us/en/glossary/relative-path/
let downloadMap: [String: String] = [
    "https://github.com/ggml-org/llama.cpp/releases/download/b7897/llama-b7897-xcframework.zip": ".",
    "https://huggingface.co/jc-builds/Qwen2.5-0.5B-Instruct-Q4_K_M-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true": "EventProcessor/Resources"
]
let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath

func downloadAndProcess() async {
    print("🚀 Starting asset download...")

    for (urlString, relativeFolder) in downloadMap {
        guard let url = URL(string: urlString) else { continue }
        
        let folderURL = URL(fileURLWithPath: currentPath).appendingPathComponent(relativeFolder)
        let fileDestination = folderURL.appendingPathComponent(url.lastPathComponent)

        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        print("\nFetching: \(url.lastPathComponent)")

        do {
            let (localURL, _) = try await downloadWithProgress(url: url)
            
            if url.pathExtension.lowercased() == "zip" {
                print("📦 Unzipping \(url.lastPathComponent)...")
                try unzip(fileURL: localURL, to: folderURL)
                print("✅ Extracted to: \(relativeFolder)")
            } else {
                if fileManager.fileExists(atPath: fileDestination.path) {
                    try fileManager.removeItem(at: fileDestination)
                }
                try fileManager.moveItem(at: localURL, to: fileDestination)
                print("✅ Saved to: \(relativeFolder)/\(url.lastPathComponent)")
            }
        } catch {
            print("❌ Error processing \(url.lastPathComponent): \(error)")
        }
    }
    print("\n✨ All tasks complete.")
}

// MARK: - Helpers

func downloadWithProgress(url: URL) async throws -> (URL, URLResponse) {
    let session = URLSession(configuration: .default)
    let observation = NSKeyValueObservation.self
    
    return try await withCheckedThrowingContinuation { continuation in
        let task = session.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let localURL = localURL {
                // Move to a temporary location because the original will be deleted
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: localURL, to: tempURL)
                continuation.resume(returning: (tempURL, response!))
            }
        }
        
        // Progress tracking
        let _ = task.progress.observe(\.fractionCompleted) { progress, _ in
            let percent = Int(progress.fractionCompleted * 100)
            print("\rProgress: [\(String(repeating: "=", count: percent/5))\(String(repeating: " ", count: 20 - percent/5))] \(percent)%", terminator: "")
            fflush(stdout)
        }
        
        task.resume()
    }
}

func unzip(fileURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    // -o overwrites, -d specifies destination
    process.arguments = ["-o", fileURL.path, "-d", destinationURL.path]
    try process.run()
    process.waitUntilExit()
}

// Entry point for async script
Task {
    await downloadAndProcess()
    exit(0)
}

dispatchMain()