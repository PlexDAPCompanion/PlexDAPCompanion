import Foundation

struct PlexPlaylist: Decodable, Identifiable {
    let id = UUID()
    let ratingKey: String?
    let title: String
    let leafCount: Int?
    let key: String?
    var isSelected: Bool = true

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case leafCount
        case key
    }
}

struct PlexPlaylistResponse: Decodable {
    let MediaContainer: PlaylistMediaContainer
}

struct PlaylistMediaContainer: Decodable {
    let Metadata: [PlexPlaylist]?
}

// Track Models
struct PlexTrack: Decodable, Identifiable {
    var id: String { ratingKey }
    let ratingKey: String
    let title: String
    let key: String
    let Media: [PlexMedia]
}

struct PlexMedia: Decodable {
    let Part: [PlexPart]
}

struct PlexPart: Decodable {
    let file: String
}

struct PlexTrackResponse: Decodable {
    let MediaContainer: TrackContainer
}

struct TrackContainer: Decodable {
    let Metadata: [PlexTrack]?
}

class PlaylistService {
    
    static func fetchPlaylists(from server: PlexResource) async -> [PlexPlaylist] {
        let connection = server.connections?.first(where: { $0.local }) ?? server.connections?.first
        guard var baseUri = connection?.uri,
              let token = server.accessToken ?? PlexAuthService.shared.authToken else {
            return []
        }

        if baseUri.hasSuffix("/") { baseUri.removeLast() }

        guard let url = URL(string: "\(baseUri)/playlists?X-Plex-Token=\(token)") else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(PlexPlaylistResponse.self, from: data)
            return decoded.MediaContainer.Metadata ?? []
        } catch {
            print("❌ Playlist Fetch Error: \(error)")
            return []
        }
    }

    static func fetchTracks(for playlist: PlexPlaylist, from server: PlexResource) async -> [PlexTrack] {
        let connection = server.connections?.first(where: { $0.local }) ?? server.connections?.first
        guard let baseUri = connection?.uri,
              let token = server.accessToken ?? PlexAuthService.shared.authToken,
              let playlistKey = playlist.key else { return [] }

        let urlString = "\(baseUri)\(playlistKey)?X-Plex-Token=\(token)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(PlexTrackResponse.self, from: data)
            
            if let firstTrack = decoded.MediaContainer.Metadata?.first {
                let path = firstTrack.Media.first?.Part.first?.file ?? "Unknown"
                print("📍 SERVER PATH EXAMPLE: \(path)")
            }

            return decoded.MediaContainer.Metadata ?? []
        } catch {
            print("❌ Track Fetch Error: \(error)")
            return []
        }
    }

    // --- IMPORT & RESTORE LOGIC ---

    // 🆕 NEW: Truth-check helper to poll Plex after an import
    static func fetchPlaylistTracksByName(name: String, on server: PlexResource) async -> [String] {
        let allPlaylists = await fetchPlaylists(from: server)
        // Find the one we just created (matching the title)
        guard let newPlaylist = allPlaylists.first(where: { $0.title == name }) else {
            print("❌ Verification: Could not find playlist named '\(name)'")
            return []
        }
        
        // Fetch the tracks inside it
        let tracks = await fetchTracks(for: newPlaylist, from: server)
        
        // Return the raw file paths from Plex
        return tracks.compactMap { $0.Media.first?.Part.first?.file }
    }

    static func findTrackID(for path: String, on server: PlexResource) async -> String? {
        let connection = server.connections?.first(where: { $0.local }) ?? server.connections?.first
        guard let baseUri = connection?.uri,
              let token = server.accessToken ?? PlexAuthService.shared.authToken else { return nil }

        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        
        var components = URLComponents(string: "\(baseUri)/library/all")
        components?.queryItems = [
            URLQueryItem(name: "file", value: cleanedPath),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Container-Size", value: "1"),
            URLQueryItem(name: "Accept", value: "application/json")
        ]
        
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let container = json["MediaContainer"] as? [String: Any],
               let metadata = container["Metadata"] as? [[String: Any]],
               let firstTrack = metadata.first,
               let ratingKey = firstTrack["ratingKey"] as? String {
                return ratingKey
            }
            return nil
        } catch {
            print("❌ Network Error during findTrackID: \(error.localizedDescription)")
            return nil
        }
    }

    static func createPlaylist(name: String, trackIDs: [String], on server: PlexResource) async {
        let connection = server.connections?.first(where: { $0.local }) ?? server.connections?.first
        guard let baseUri = connection?.uri,
              let token = server.accessToken ?? PlexAuthService.shared.authToken,
              let machineID = server.clientIdentifier else {
            return
        }

        let ids = trackIDs.joined(separator: ",")
        let playlistUri = "server://\(machineID)/com.plexapp.plugins.library/library/metadata/\(ids)"
        
        var components = URLComponents(string: "\(baseUri)/playlists")
        components?.queryItems = [
            URLQueryItem(name: "uri", value: playlistUri),
            URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "smart", value: "0"),
            URLQueryItem(name: "type", value: "audio"),
            URLQueryItem(name: "includeExternalMedia", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        
        guard let url = components?.url else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    print("✅ Playlist '\(name)' created successfully!")
                }
            }
        } catch {
            print("❌ Request Error: \(error.localizedDescription)")
        }
    }
}
