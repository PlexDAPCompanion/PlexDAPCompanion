import Foundation
import AVFoundation
import AppKit

class ArtworkService {
    static let shared = ArtworkService()
    
    // Valid artwork filenames to check for skipping
    let validArtNames = ["cover.jpg", "folder.jpg", "album.jpg", "cover.png", "folder.png"]
    
    // MARK: - Native Swift Scan (Extract Art)
    
    func scanAndFixArtwork(at rootURL: URL, progressUpdate: @escaping (String) -> Void) async -> (created: Int, skipped: Int, failed: Int) {
        var created = 0
        var skipped = 0
        var failed = 0
        
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return (0, 0, 0)
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Give the UI thread room to breathe
            await Task.yield()
            
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  resourceValues.isDirectory == true else { continue }
            
            // 1. Check if artwork already exists
            let hasArt = validArtNames.contains { name in
                fileManager.fileExists(atPath: fileURL.appendingPathComponent(name).path)
            }
            
            if hasArt {
                skipped += 1
                continue
            }
            
            // 2. Find audio files in this folder
            let audioFiles = (try? fileManager.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil))?
                .filter { ["mp3", "flac", "m4a"].contains($0.pathExtension.lowercased()) } ?? []
            
            if audioFiles.isEmpty { continue }
            
            // 3. Attempt to extract art
            var foundArt = false
            for audioURL in audioFiles {
                if let artworkData = await extractArtwork(from: audioURL) {
                    if saveResizedImage(data: artworkData, to: fileURL.appendingPathComponent("folder.jpg")) {
                        created += 1
                        foundArt = true
                        progressUpdate("✅ Created: \(fileURL.lastPathComponent)")
                        break
                    }
                }
            }
            
            if !foundArt {
                failed += 1
                progressUpdate("❌ Missing: \(fileURL.lastPathComponent)")
            }
        }
        
        return (created, skipped, failed)
    }
    
    // MARK: - Python Bridge (Inject Art)
    
    /// Launches the bundled Python script to inject .jpg files back into track metadata
    func runPythonInjection(at folderPath: String, progressUpdate: @escaping (String) -> Void) async {
        let task = Process()
        let pipe = Pipe()
        
        // 1. Locate the script inside the App Bundle
        guard let scriptURL = Bundle.main.url(forResource: "inject_art", withExtension: "py") else {
            progressUpdate("❌ Error: inject_art.py missing from bundle.")
            return
        }
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = [scriptURL.path, folderPath]
        
        // Use the system python3 path
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        
        do {
            try task.run()
            
            let reader = pipe.fileHandleForReading
            
            // Stream the output line-by-line using Swift 6 AsyncSequence
            // This ensures the UI updates the moment Python prints a '✅ FIXED' line
            for try await line in reader.bytes.lines {
                progressUpdate(line)
            }
            
            task.waitUntilExit()
        } catch {
            progressUpdate("❌ Failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func extractArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        
        let artworkItems = AVMetadataItem.metadataItems(
            from: metadata,
            withKey: AVMetadataKey.commonKeyArtwork,
            keySpace: AVMetadataKeySpace.common
        )
        
        guard let firstItem = artworkItems.first else { return nil }
        
        do {
            // Casting to Any? first silences the compiler warning for redundant downcasts
            let value: Any? = try await firstItem.load(.dataValue)
            return value as? Data
        } catch {
            return nil
        }
    }
    
    private func saveResizedImage(data: Data, to destination: URL) -> Bool {
        guard let originalImage = NSImage(data: data) else { return false }
        
        let targetSize = NSSize(width: 500, height: 500)
        let ratio = min(targetSize.width / originalImage.size.width, targetSize.height / originalImage.size.height)
        let newSize = NSSize(width: originalImage.size.width * ratio, height: originalImage.size.height * ratio)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        originalImage.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return false
        }
        
        do {
            try jpegData.write(to: destination)
            return true
        } catch {
            return false
        }
    }
}
