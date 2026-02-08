import Foundation
import AppKit
import UniformTypeIdentifiers

struct M3UExporter {
    static func export(
        playlistName: String,
        tracks: [PlexTrack],
        serverPrefix: String,
        dapPrefix: String,
        folderURL: URL? = nil,
        isBackup: Bool = false 
    ) {
        // 1. Start with the Rockbox-friendly header and Windows-style line endings
        var m3uContent = "#EXTM3U\r\n"
        
        for track in tracks {
            if let firstPart = track.Media.first?.Part.first {
                let serverPath = firstPart.file
                
                var finalPath: String
                
                if isBackup {
                    // 🛡 Backup Mode: Keep the raw Plex path exactly as it is
                    finalPath = serverPath
                } else {
                    // 🔄 DAP Mode: The Rockbox/DAP Path Swap
                    var dapPath = serverPath.replacingOccurrences(of: serverPrefix, with: dapPrefix)
                    
                    // 🛠 Fix for Mac vs Rockbox character encoding (NFC Normalization)
                    dapPath = dapPath.precomposedStringWithCanonicalMapping
                    finalPath = dapPath
                }
                
                m3uContent += "#EXTINF:-1,\(track.title)\r\n"
                m3uContent += "\(finalPath)\r\n"
            }
        } // End of tracks loop
        
        // --- SAVE LOGIC ---
        
        if let folder = folderURL {
            // Batch Mode (Exporting multiple playlists at once)
            let fileName = "\(playlistName).m3u8"
            let fileURL = folder.appendingPathComponent(fileName)
            
            do {
                // Encode with UTF-8 and add the Byte Order Mark (BOM) for Rockbox/FiiO/Plex
                if let data = m3uContent.data(using: .utf8) {
                    let bom = Data([0xEF, 0xBB, 0xBF])
                    var outData = bom
                    outData.append(data)
                    
                    try outData.write(to: fileURL)
                    print("✅ \(isBackup ? "Backed up" : "Exported"): \(fileName)")
                }
            } catch {
                print("❌ Failed to write \(fileName): \(error)")
            }
            
        } else {
            // Manual Single Save Mode (Original Logic)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.m3uPlaylist]
            savePanel.nameFieldStringValue = "\(playlistName).m3u8"
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                if let data = m3uContent.data(using: .utf8) {
                    let bom = Data([0xEF, 0xBB, 0xBF])
                    var outData = bom
                    outData.append(data)
                    try? outData.write(to: url)
                }
            }
        }
    } // End of export function
} // End of M3UExporter struct
