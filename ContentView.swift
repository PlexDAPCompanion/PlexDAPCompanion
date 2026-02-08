import SwiftUI
import Foundation
import UniformTypeIdentifiers

// --- Data Models ---

enum ExportMode {
    case dap, backup, importing
}

struct ExportLog: Identifiable {
    let id = UUID()
    let playlistName: String
    let examplePath: String
    let transformedPath: String
    let isWarning: Bool
}

struct ImportReconciliation: Identifiable {
    let id = UUID()
    let fileName: String
    let fullPath: String
    let isInPlex: Bool
}

struct ContentView: View {
    // --- State & AppStorage ---
    @State private var playlists: [PlexPlaylist] = []
    @State private var activeExportMode: ExportMode? = nil
    @State private var selectedServer: PlexResource?
    @State private var servers: [PlexResource] = []
    @State private var exportedCount = 0
    @State private var exportLogs: [ExportLog] = []
    @State private var showLogSheet = false
    @State private var lastExportURL: URL?
    @State private var showPathInfo = false
    
    // Artwork Fixer State
    @State private var isRunningArtworkFix = false
    @State private var isRunningDeepInjection = false
    @State private var artworkLog: String = ""
    
    // UI for Reconciliation Sheet
    @State private var reconciliationResults: [ImportReconciliation] = []
    @State private var showReconciliationSheet = false
    @State private var currentImportingPlaylistName: String = ""
    @State private var currentImportingPaths: [String] = []
    
    @AppStorage("serverPrefix") private var serverPrefix: String = "/Volumes/Plex/Music/"
    @AppStorage("dapPrefix") private var dapPrefix: String = "/Music/"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Settings Bar
            VStack(spacing: 16) {
                HStack {
                    Picker("Server", selection: $selectedServer) {
                        Text("Select a Server").tag(nil as PlexResource?)
                        ForEach(servers, id: \.name) { server in
                            Text(server.name).tag(server as PlexResource?)
                        }
                    }
                    Button("Fetch") { Task { await loadPlaylists() } }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Path Mapping").font(.headline)
                        Spacer()
                        Button(action: { showPathInfo = true }) {
                            Image(systemName: "info.circle").foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack {
                        Text("Server Prefix:").font(.subheadline).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                        TextField("Path to remove", text: $serverPrefix).textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("DAP Prefix:").font(.subheadline).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                        TextField("Path to add", text: $dapPrefix).textFieldStyle(.roundedBorder)
                    }
                }
                .alert("How Path Mapping Works", isPresented: $showPathInfo) {
                    Button("Got it", role: .cancel) { }
                } message: {
                    Text("Type the directory of your Plex music library into the Server Prefix field. Type the path of your DAP music folder in the DAP Prefix Field.\n\nThis app replaces the 'Server Prefix' with the 'DAP Prefix' in your playlist files so that you can play your plex playlists on your DAP.\n\n Use the Save Embedded Cover Art button to search your directories for albums that have album artwork embedded in the music files and save them as .jpg files. This helps with compatibility on some DAPs and with Plex. \n\nUse the Inject Album Artwork button to first check if there are any tracks without embedded album artwork and then add the .jpg files into the metadata.")
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // Library Maintenance Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Library Maintenance").font(.headline)
                
                HStack(spacing: 12) {
                    // Button 1: Swift Artwork Extraction
                    Button(action: runArtworkFix) {
                        HStack {
                            if isRunningArtworkFix {
                                ProgressView().controlSize(.small).padding(.trailing, 5)
                            }
                            Label("Save Embedded Art as .jpg", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningArtworkFix || isRunningDeepInjection)
                    
                    // Button 2: Python Artwork Injection
                    Button(action: runDeepInjection) {
                        HStack {
                            if isRunningDeepInjection {
                                ProgressView().controlSize(.small).padding(.trailing, 5)
                            }
                            Label("Inject .jpg into Tracks", systemImage: "paintbrush.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningArtworkFix || isRunningDeepInjection)
                    
                    if !artworkLog.isEmpty {
                        Text(artworkLog)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()

            if !playlists.isEmpty {
                HStack {
                    Button("Select All") { setAll(to: true) }
                    Button("None") { setAll(to: false) }
                    Spacer()
                    
                    Button(action: importToPlex) {
                        HStack {
                            if activeExportMode == .importing { ProgressView().controlSize(.small).padding(.trailing, 5) }
                            Label("Import to Plex", systemImage: "arrow.up.doc")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeExportMode != nil)
                    
                    Button(action: { batchExport(asBackup: true) }) {
                        HStack {
                            if activeExportMode == .backup { ProgressView().controlSize(.small).padding(.trailing, 5) }
                            Label("Backup Plex Format", systemImage: "arrow.down.doc")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeExportMode != nil || !playlists.contains(where: { $0.isSelected }))
                    
                    Button(action: { batchExport(asBackup: false) }) {
                        HStack {
                            if activeExportMode == .dap { ProgressView().controlSize(.small).padding(.trailing, 5) }
                            Text("Export for DAP")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(activeExportMode != nil || !playlists.contains(where: { $0.isSelected }))
                }
                .padding()
            }
            
            List($playlists) { $playlist in
                HStack {
                    Toggle("", isOn: $playlist.isSelected).labelsHidden()
                    VStack(alignment: .leading) {
                        Text(playlist.title).font(.headline)
                        Text("\(playlist.leafCount ?? 0) tracks").font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear { setupInitialServers() }
        .sheet(isPresented: $showReconciliationSheet) {
            ReconciliationSheet(
                results: reconciliationResults,
                playlistName: currentImportingPlaylistName,
                allPaths: currentImportingPaths,
                server: selectedServer
            ) { updatedResults in
                self.reconciliationResults = updatedResults
            }
        }
        .sheet(isPresented: $showLogSheet) {
            ExportLogSheet(logs: exportLogs, lastURL: lastExportURL)
        }
    }
    
    // --- Core Logic ---
    
    func setupInitialServers() {
        Task {
            await PlexAuthService.shared.fetchResources()
            await MainActor.run {
                self.servers = PlexAuthService.shared.servers
                self.selectedServer = self.servers.first
            }
        }
    }
    
    func setAll(to value: Bool) {
        for i in 0..<playlists.count { playlists[i].isSelected = value }
    }
    
    func loadPlaylists() async {
        guard let server = selectedServer else { return }
        let fetched = await PlaylistService.fetchPlaylists(from: server)
        await MainActor.run {
            self.playlists = fetched.map {
                var p = $0
                p.isSelected = (p.title != "All Music")
                return p
            }
        }
    }

    func runArtworkFix() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select your Music root folder to extract embedded art"
        
        if panel.runModal() == .OK, let folderURL = panel.url {
            isRunningArtworkFix = true
            artworkLog = "Initializing scan..."
            
            Task {
                let result = await ArtworkService.shared.scanAndFixArtwork(at: folderURL) { update in
                    Task { @MainActor in
                        self.artworkLog = update
                    }
                }
                
                await MainActor.run {
                    self.artworkLog = "Finished: \(result.created) created, \(result.skipped) skipped."
                    self.isRunningArtworkFix = false
                }
            }
        }
    }

    // NEW: Python Injection Logic
    func runDeepInjection() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select Music folder to inject .jpg files into metadata"
        
        if panel.runModal() == .OK, let folderURL = panel.url {
            isRunningDeepInjection = true
            artworkLog = "Launching Python engine..."
            
            Task {
                await ArtworkService.shared.runPythonInjection(at: folderURL.path) { update in
                    Task { @MainActor in
                        // Filter out empty lines or noise from Python
                        if !update.trimmingCharacters(in: .whitespaces).isEmpty {
                            self.artworkLog = update
                        }
                    }
                }
                
                await MainActor.run {
                    self.artworkLog = "Deep Injection Complete."
                    self.isRunningDeepInjection = false
                }
            }
        }
    }

    func importToPlex() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.m3uPlaylist]
        panel.message = "Select an .m3u8 backup to import"
        
        if panel.runModal() == .OK, let fileURL = panel.url {
            activeExportMode = .importing
            
            Task {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                      let server = selectedServer else {
                    await MainActor.run { activeExportMode = nil }
                    return
                }
                
                let lines = content.components(separatedBy: .newlines)
                let allPaths = lines.filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                
                var foundIDs: [String] = []
                for path in allPaths {
                    if let id = await PlaylistService.findTrackID(for: path, on: server) {
                        foundIDs.append(id)
                    }
                }
                
                let originalName = fileURL.deletingPathExtension().lastPathComponent
                let playlistName = "\(originalName) (Imported)"
                
                if !foundIDs.isEmpty {
                    await PlaylistService.createPlaylist(name: playlistName, trackIDs: foundIDs, on: server)
                }
                
                var actualPlexPaths: [String] = []
                var retryCount = 0
                let maxRetries = 5

                while retryCount < maxRetries {
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                    actualPlexPaths = await PlaylistService.fetchPlaylistTracksByName(name: playlistName, on: server)
                    if actualPlexPaths.count >= foundIDs.count { break }
                    retryCount += 1
                }
                
                let results = allPaths.map { path -> ImportReconciliation in
                    let fileName = path.components(separatedBy: "/").last ?? path
                    let isVerified = actualPlexPaths.contains { plexPath in
                        plexPath.precomposedStringWithCanonicalMapping == path.precomposedStringWithCanonicalMapping
                    }
                    return ImportReconciliation(fileName: fileName, fullPath: path, isInPlex: isVerified)
                }
                
                await MainActor.run {
                    self.currentImportingPlaylistName = playlistName
                    self.currentImportingPaths = allPaths
                    self.reconciliationResults = results
                    self.showReconciliationSheet = true
                    self.activeExportMode = nil
                    Task { await loadPlaylists() }
                }
            }
        }
    }

    func batchExport(asBackup: Bool = false) {
        guard let server = selectedServer else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = asBackup ? "Select backup folder" : "Select export folder"
        
        if panel.runModal() == .OK, let folderURL = panel.url {
            activeExportMode = asBackup ? .backup : .dap
            exportLogs = []
            
            Task {
                var count = 0
                for playlist in playlists where playlist.isSelected {
                    let tracks = await PlaylistService.fetchTracks(for: playlist, from: server)
                    let samplePath = tracks.first?.Media.first?.Part.first?.file ?? "No path"
                    
                    M3UExporter.export(
                        playlistName: playlist.title,
                        tracks: tracks,
                        serverPrefix: self.serverPrefix,
                        dapPrefix: self.dapPrefix,
                        folderURL: folderURL,
                        isBackup: asBackup
                    )
                    
                    await MainActor.run {
                        let transformed = asBackup ? samplePath : samplePath.replacingOccurrences(of: self.serverPrefix, with: self.dapPrefix)
                        let warning = !asBackup && transformed.count > 200
                        exportLogs.append(ExportLog(playlistName: playlist.title, examplePath: samplePath, transformedPath: transformed, isWarning: warning))
                    }
                    count += 1
                }
                await MainActor.run {
                    self.exportedCount = count
                    self.lastExportURL = folderURL
                    activeExportMode = nil
                    showLogSheet = true
                }
            }
        }
    }
}
// --- Supporting Views ---

struct ReconciliationSheet: View {
    let results: [ImportReconciliation]
    let playlistName: String
    let allPaths: [String]
    let server: PlexResource?
    var onUpdate: ([ImportReconciliation]) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plex Import Verification").font(.title2).bold()
                    
                    Text("\(results.filter { $0.isInPlex }.count) of \(results.count) tracks verified.")
                        .font(.headline)
                        .foregroundColor(results.count == results.filter{$0.isInPlex}.count ? .green : .orange)
                    
                    Text("Please review all unmatched (\(results.filter { !$0.isInPlex }.count)) songs as the Plex API may have not imported it at all or imported the wrong song.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        if isRefreshing { ProgressView().controlSize(.small) }
                        Button("Verify Again") { refreshVerification() }.disabled(isRefreshing)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    
                    Button(action: saveReconciliationReport) {
                        Label("Save Report (.txt)", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Table(results) {
                TableColumn("Status") { row in
                    Image(systemName: row.isInPlex ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(row.isInPlex ? .green : .red)
                }.width(50)
                
                TableColumn("File Name") { row in
                    Text(row.fileName)
                        .foregroundColor(row.isInPlex ? .primary : .red)
                        .fontWeight(row.isInPlex ? .regular : .bold)
                }
                
                TableColumn("Full Path") { row in
                    Text(row.fullPath).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 850, minHeight: 550)
    }
    
    func saveReconciliationReport() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(playlistName)_Import_Report.txt"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            var report = "PLEX IMPORT REPORT: \(playlistName)\n"
            report += "Generated on: \(Date().formatted())\n"
            report += "Summary: \(results.filter { $0.isInPlex }.count) / \(results.count) tracks verified.\n"
            report += "--------------------------------------------------\n\n"
            
            let failed = results.filter { !$0.isInPlex }
            if !failed.isEmpty {
                report += "⚠️ UNMATCHED TRACKS:\n"
                for item in failed {
                    report += "- \(item.fileName)\n  Path: \(item.fullPath)\n\n"
                }
                report += "--------------------------------------------------\n\n"
            }
            
            report += "✅ VERIFIED TRACKS:\n"
            for item in results.filter({ $0.isInPlex }) {
                report += "- \(item.fileName)\n"
            }
            
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    func refreshVerification() {
        guard let server = server else { return }
        isRefreshing = true
        Task {
            let actualPlexPaths = await PlaylistService.fetchPlaylistTracksByName(name: playlistName, on: server)
            let updated = allPaths.map { path -> ImportReconciliation in
                let fileName = path.components(separatedBy: "/").last ?? path
                let isVerified = actualPlexPaths.contains { plexPath in
                    plexPath.precomposedStringWithCanonicalMapping == path.precomposedStringWithCanonicalMapping
                }
                return ImportReconciliation(fileName: fileName, fullPath: path, isInPlex: isVerified)
            }
            
            await MainActor.run {
                onUpdate(updated)
                isRefreshing = false
            }
        }
    }
}

struct ExportLogSheet: View {
    let logs: [ExportLog]
    let lastURL: URL?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Summary").font(.title2).bold()
                Spacer()
                if let url = lastURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Label("Open Folder", systemImage: "folder")
                    }.buttonStyle(.bordered)
                }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            List(logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.isWarning ? "⚠️" : "✅")
                        Text("\(log.playlistName).m3u8").font(.headline)
                    }.foregroundColor(log.isWarning ? .orange : .green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From: \(log.examplePath)").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                        Text("To:   \(log.transformedPath)").font(.system(.caption, design: .monospaced)).foregroundColor(log.isWarning ? .red : .blue)
                    }.padding(.leading, 24)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}
