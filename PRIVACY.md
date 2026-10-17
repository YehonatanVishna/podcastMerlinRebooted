# Privacy Policy for Podcast Merlin

**Last Updated:** October 15, 2026  
**Effective Date:** October 15, 2026

Podcast Merlin ("the App", "we", "us", or "our"), developed by Yehonatan Vishna, is committed to respecting and protecting your privacy. This Privacy Policy explains our principles and practices regarding the collection, use, storage, and disclosure of information when you use the Podcast Merlin desktop and mobile applications across supported platforms (Linux, Android, Windows, macOS).

---

## 1. Core Philosophy: Local-First & Zero-Telemetry

Podcast Merlin is built around a **local-first and privacy-respecting architecture**:
- **No Analytics or Telemetry:** We do not collect, store, or transmit telemetry data, crash statistics, usage patterns, or behavioral metrics.
- **No Advertising:** The App does not contain third-party advertising SDKs, ad networks, tracking pixels, or device fingerprinting tools.
- **No Account Required with Us:** You do not need to register an account with Podcast Merlin or provide personal identity information (such as your name, email address, or phone number) to use the App.

---

## 2. Information Handled & Local Storage

All essential data created while using Podcast Merlin is stored locally on your device:

1. **Podcast Subscriptions & Metadata:** RSS feed URLs, podcast titles, artwork URLs, and episode descriptions are saved in a local SQLite database on your device.
2. **Playback State & History:** Playback progress, episode completion status, "Up Next" queue orders, and listening history remain strictly on your local device unless you explicitly enable synchronization.
3. **Downloads & Cache:** Audio files downloaded for offline listening and cached podcast artwork images are stored solely within your device's local application storage directory.
4. **Application Settings:** User preferences (e.g., playback speeds, skip durations, theme selection, sleep timer presets) are stored locally on your device.

---

## 3. Network Communication & External Services

Because Podcast Merlin is a podcast player and manager, it interacts over the internet in the following specific contexts:

### A. Fetching RSS Feeds & Streaming/Downloading Audio
- When you subscribe to a show, refresh feeds, or stream/download an episode, Podcast Merlin establishes a direct network connection to the server or Content Delivery Network (CDN) hosting the RSS feed or media file.
- These requests are sent directly from your device to the podcast publishers' third-party hosting servers. Like any standard HTTP/HTTPS web request, the hosting server will see your IP address, timestamp, and standard request headers (including user-agent and requested byte ranges). Such third-party servers operate according to their own independent privacy policies and terms of service.

### B. Nextcloud & gPodder Synchronization (Optional)
- **User-Directed Sync:** If you choose to configure bi-directional synchronization via Nextcloud (Nextcloud Podcast app) or gPodder (gPodder.net or a self-hosted gPodder API instance), Podcast Merlin communicates directly with your chosen server.
- **Data Transmitted:** Only your podcast subscriptions, episode playback positions, and subscription changes are synchronized with that server.
- **No Intermediary:** Data flows directly between your device and your designated server. Podcast Merlin developers operate no intermediary proxy and have no access to your sync credentials or playback data.

### C. Podcast Discovery (Apple Podcasts / iTunes Search API)
- The discovery feature enables finding podcasts via the public Apple Podcasts / iTunes Search API.
- Search queries you submit in the Discovery view are transmitted directly to Apple's public search endpoint. No user account or identifying data is transmitted with your search queries.

---

## 4. Credential Storage & Security

If you use sync features requiring authentication:
- **Encrypted Local Storage:** Usernames, passwords, and authentication tokens are encrypted and stored in your operating system's native secure credential facility via `flutter_secure_storage`:
  - **Android:** Android KeyStore with EncryptedSharedPreferences (AES encryption)
  - **Linux:** Secret Service API / `libsecret`
  - **macOS:** Apple Keychain
  - **Windows:** Windows Credential Manager / Data Protection API (DPAPI)
- Credentials are never transmitted to any third party other than your explicitly configured synchronization server over HTTPS (or unencrypted HTTP if you specifically override security warnings for self-hosted local servers).

---

## 5. Device Permissions

Depending on your platform (e.g., Android, Linux, Windows, macOS), the App may request the following permissions solely to perform its intended playback and management functions:

| Permission | Purpose |
| :--- | :--- |
| **Internet Access** (`INTERNET` / `internetClient`) | Required to download RSS feeds, stream audio enclosures, fetch artwork, query discovery search, and perform sync. |
| **Foreground Service & Media Playback** (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`) | Required on Android to maintain uninterrupted background audio playback and system notification controls when the app is minimized. |
| **Wake Lock** (`WAKE_LOCK`) | Prevents the CPU from sleeping during active audio playback while the screen is turned off. |
| **Post Notifications** (`POST_NOTIFICATIONS`) | Displays active media playback controls and sync progress in the system notification shade. |

The App does not request access to contacts, location, camera, microphone, or unrelated personal device sensors.

---

## 6. Data Portability, Retention & Deletion

- **OPML Export:** You can export your entire podcast subscription list at any time to an industry-standard OPML (Outline Processor Markup Language) file via Settings.
- **Data Deletion:**
  - You can delete individual podcasts, clear downloaded media files, or purge image cache directly within the App's interface.
  - Clearing application data or uninstalling Podcast Merlin immediately deletes all locally stored databases, cache, downloaded episodes, and stored credentials from your device.
  - If you use an external sync service (Nextcloud or gPodder), data stored on that external server is managed according to that server's retention and deletion policies.

---

## 7. Children's Privacy

Podcast Merlin does not knowingly collect or solicit personal information from children under the age of 13 (or 16 in the European Union). Because the App does not collect personal data from any user, no personal information of minors is retained or processed.

---

## 8. Changes to This Privacy Policy

We may update this Privacy Policy from time to time to reflect changes in our practices or applicable laws. Any revisions will be published in the project's source repository with an updated "Last Updated" date. We encourage you to review this policy periodically.

---

## 9. Contact & Inquiries

If you have questions, feedback, or concerns regarding this Privacy Policy or Podcast Merlin's privacy practices, please contact us:

- **GitHub Repository & Issue Tracker:** [https://github.com/YehonatanVishna/podcastMerlinRebooted/issues](https://github.com/YehonatanVishna/podcastMerlinRebooted/issues)
- **Maintainer:** Yehonatan Vishna
