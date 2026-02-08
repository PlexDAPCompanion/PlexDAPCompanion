import Foundation
import SwiftUI
import Combine

// MARK: - Models
struct PlexPin: Decodable {
    let id: Int
    let code: String
}

struct PlexResource: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let provides: String
    let accessToken: String?
    let connections: [PlexConnection]?
    let clientIdentifier: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PlexResource, rhs: PlexResource) -> Bool {
        lhs.id == rhs.id
    }
}

struct PlexConnection: Decodable {
    let uri: String
    let local: Bool
}

// MARK: - Service
@MainActor
final class PlexAuthService: ObservableObject {
    
    @Published var isAuthenticated = false
    @Published var authToken: String? = nil
    @Published var statusMessage: String = "Not connected"
    @Published var servers: [PlexResource] = []
    
    static let shared = PlexAuthService()
    
    private let clientID = "A3C2F9C2-8E4C-4F2B-9C31-D38E22D11234"
    private let productName = "Plex DAP Companion"
    private var pinID: Int?
    private var pollTask: Task<Void, Never>?
    
    private init() {
        if let savedToken = KeychainHelper.load() {
            self.authToken = savedToken
            self.isAuthenticated = true
            self.statusMessage = "Logged in"
            Task { await fetchResources() }
        }
    }
    
    private func applyPlexHeaders(to request: inout URLRequest) {
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
        request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }
    
    func connectToPlex() {
        statusMessage = "Requesting Plex PIN…"
        Task {
            do {
                let pin = try await createPin()
                self.pinID = pin.id
                openAuthWindow(pin: pin)
                startPolling()
            } catch {
                statusMessage = "Failed to create PIN"
            }
        }
    }
    
    private func createPin() async throws -> PlexPin {
        var components = URLComponents(string: "https://plex.tv/api/v2/pins")!
        components.queryItems = [URLQueryItem(name: "strong", value: "true")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        applyPlexHeaders(to: &request)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }
    
    private func openAuthWindow(pin: PlexPin) {
        let product = productName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let authURLString = "https://app.plex.tv/auth#?clientID=\(clientID)&code=\(pin.code)&context%5Bdevice%5D%5Bproduct%5D=\(product)"
        if let url = URL(string: authURLString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkPin()
            }
        }
    }
    
    private func checkPin() async {
        guard let pinID = pinID else { return }
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins/\(pinID)")!)
        applyPlexHeaders(to: &request)
        
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["authToken"] as? String {
            
            self.authToken = token
            self.isAuthenticated = true
            KeychainHelper.save(token)
            pollTask?.cancel()
            await fetchResources()
        }
    }
    
    func fetchResources() async {
        guard let token = authToken else { return }
        
        var components = URLComponents(string: "https://plex.tv/api/v2/resources")!
        components.queryItems = [URLQueryItem(name: "includeHttps", value: "1")]
        
        var request = URLRequest(url: components.url!)
        applyPlexHeaders(to: &request)
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                print("🛑 Token is invalid or revoked. Resetting...")
                logout()
                return // 
            }
            
            // Successfully got data!
            let allResources = try JSONDecoder().decode([PlexResource].self, from: data)
            self.servers = allResources.filter { $0.provides.lowercased().contains("server") }
            
            if self.servers.isEmpty {
                self.statusMessage = "Logged in, but no servers found."
            } else {
                for server in self.servers {
                    let firstUri = server.connections?.first?.uri ?? "No URI"
                    print("🖥️ Found Server: \(server.name) - \(firstUri)")
                }
                self.statusMessage = "Found \(servers.count) server(s)"
            }
            
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return }
            print("❌ Resource Fetch Error: \(error)")
            statusMessage = "Error finding servers."
        }
    }
    
    func logout() {
        KeychainHelper.delete()
        self.authToken = nil
        self.isAuthenticated = false
        self.servers = []
        self.statusMessage = "Please connect to Plex."
        print("🧹 App state cleared and Keychain deleted.")
    }
}
