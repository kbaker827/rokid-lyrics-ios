# Rokid Lyrics iOS


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

iOS companion app for Rokid AR glasses that displays real-time synchronized song lyrics.  
Converted from the [Android original](https://github.com/Anezium/awesome-rokid).

## Architecture

```
iPhone (this app)                    Rokid Glasses (Android, unchanged)
─────────────────                    ──────────────────────────────────
NowPlayingMonitor                    Lyrics glasses app
  └─ MPNowPlayingInfoCenter poll       └─ connects via Wi-Fi TCP :8081
       │
LyricsRuntimeEngine
  └─ CompositeLyricsProvider
       ├─ MusixmatchProvider (HMAC-SHA1)
       ├─ NeteaseProvider (AES+RSA weapi)
       └─ LrcLibClient (public REST)
       │
GlassesServer (NWListener TCP :8081)
  └─ WireProtocol (JSON+newline framing)
       └─ sends: snapshot / sync / status / hello_ack
       └─ receives: hello / request_snapshot / request_status / toggle_playback
```

## File Reference

| File | Purpose |
|------|---------|
| `Protocol/LyricsContracts.swift` | All message types mirroring `LyricsContracts.kt` |
| `Protocol/WireProtocol.swift` | JSON envelope encode/decode mirroring `WireProtocol.kt` |
| `Media/NowPlayingMonitor.swift` | Polls `MPNowPlayingInfoCenter` (replaces Android `MediaSessionMonitor`) |
| `Lyrics/LyricsModels.swift` | `LyricsLookupRequest`, `FetchedLyrics` |
| `Lyrics/LrcLibClient.swift` | LRCLib REST API (cached → exact → search with scoring) |
| `Lyrics/MusixmatchProvider.swift` | HMAC-SHA1 signed Musixmatch API |
| `Lyrics/NeteaseProvider.swift` | Netease weapi (AES/CBC + RSA modPow) |
| `Lyrics/CompositeLyricsProvider.swift` | Tries Musixmatch → Netease → LRCLib |
| `Lyrics/LyricsRuntimeEngine.swift` | Track change detection, lookup lifecycle, progress sync |
| `Glasses/GlassesServer.swift` | `NWListener` TCP server on port 8081 |
| `ViewModel/LyricsViewModel.swift` | Orchestrates all services, broadcasts to glasses |
| `UI/MainView.swift` | Tab container: Now Playing + Settings |
| `UI/LyricsView.swift` | Past/current/next synced lyrics display |
| `UI/LyricsLineView.swift` | Styled single line (past/current/next1/next2 roles) |
| `UI/SettingsView.swift` | Connection info, IP address |

## Xcode Setup

1. Open `RokidLyrics.xcodeproj` in Xcode 15+
2. Select your Team under **Signing & Capabilities**
3. In **Capabilities**, add **Background Modes → Audio** (already in Info.plist)
4. Build & run on iPhone

No third-party dependencies — uses only Apple frameworks:
- `Network.framework` — `NWListener` TCP server
- `MediaPlayer.framework` — `MPNowPlayingInfoCenter` media polling
- `CommonCrypto` — AES/CBC and HMAC-SHA1
- `Security` — `SecRandomCopyBytes`

## Connecting Glasses

1. Make sure the iPhone and glasses are on the **same Wi-Fi network**
2. Open the app → **Settings** tab — note the **Phone IP** (e.g., `192.168.1.42`)
3. On the glasses, open the Rokid Lyrics app and set the server address to `192.168.1.42:8081`
4. The status bar turns green when connected

## Why Wi-Fi instead of Bluetooth?

iOS blocks generic Bluetooth RFCOMM (SPP) without MFi certification.  
The wire protocol (JSON+newline framed `WireEnvelope`) is identical to the Android version — only the transport layer changes from Bluetooth to TCP.

## Lyrics Provider Chain

1. **Musixmatch** — authenticated, best quality synced lyrics (HMAC-SHA1 signed)
2. **Netease** — Chinese music service, excellent coverage (AES weapi)
3. **LRCLib** — public REST API, no authentication required

## Playback Control Limitation

`togglePlayback` from the glasses works for **Apple Music** via `MPMusicPlayerController.systemMusicPlayer`.  
For Spotify, YouTube Music, and other apps, the toggle command is received but cannot control third-party playback due to iOS sandbox restrictions.
