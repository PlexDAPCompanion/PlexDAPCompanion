# PlexDAPCompanion 🎸

A specialized macOS utility for audiophiles who sync Plex Media Server playlists to Rockbox-powered DAPs (Digital Audio Players).

## 🚀 Features
- **Plex Integration:** Connects securely via OAuth/PIN to fetch your curated playlists directly from your server.
- **DAP Path Mapping:** Automatically translates server file paths (e.g., `/mnt/media/music`) to DAP-compatible paths (e.g., `A:\Music`) on the fly.
- **Rockbox Optimized:** Exports `.m3u8` files using **UTF-8 with BOM** and **NFC Normalization** for perfect character rendering on vintage and modern hardware.
- **Album Artwork Extraction:** Uses a Python bridge (`Mutagen`) to pull embedded album art to a 500x500px .jpg file.
- **Deep Artwork Injection:** Uses a Python bridge (`Mutagen`) to ensure album art is embedded directly into the files during export.

## 🛠 Tech Stack
- **SwiftUI:** Modern native macOS interface.
- **Python Bridge:** Bundled dependencies for advanced metadata and artwork manipulation.
- **Keychain Services:** Secure, encrypted storage of Plex authentication tokens via macOS Security framework.

## 📦 Installation & Setup
1. **Download the App:** Grab the latest version from the [Releases](#) page.
2. **Configure Mapping:** Enter your Plex Server IP and your Folder Mapping in Settings (e.g., how your Mac sees the music vs. how the DAP sees it).
3. **Connect:** Click **Connect** to link your Plex account via the secure PIN pop-up.
4. **Export:** Select a playlist, choose your destination, and hit **Export**.

## ⚠️ Requirements
- macOS 14.0 or later.
- Python 3.x installed (for the Artwork Injection module).

## 📝 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ✨Coded with Gemini
