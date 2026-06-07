# Dynamic Island für macOS

Eine Dynamic Island rund um die Notch deines MacBooks – wie beim iPhone.

- **Links neben der Notch**: Cover/Thumbnail des aktuellen Spotify-Tracks (Fallback: YouTube-Tab in Chrome).
- **Rechts neben der Notch**: Ring mit deinem Claude-Usage (rollendes 5-Stunden-Limit).
- **Hover über die Island**: Panel klappt auf und zeigt Titel/Artist/Fortschritt links und Prozent, Tokens, Reset-Zeit & Modell rechts.

Die App läuft unsichtbar im Hintergrund – **kein Dock-Icon, kein Menüleisten-Icon** – und startet automatisch beim Login.

## Installieren / Updaten

```bash
./install.sh
```

Das baut die App, kopiert sie nach `~/Applications/DynamicIsland.app` und registriert einen
LaunchAgent (`~/Library/LaunchAgents/com.julian.dynamicisland.plist`) mit `RunAtLoad` + `KeepAlive`
(startet bei Login und startet neu, falls sie je abstürzt).

## Claude-Limit (echte Anthropic-Daten)

Der Ring rechts zeigt das **echte** 5-Stunden-Session-Limit direkt von Anthropic
(`https://api.anthropic.com/api/oauth/usage`) – exakt die Zahl aus deinen Claude-Einstellungen
bzw. `/usage` in Claude Code. Beim Hover zusätzlich: Wochen-Limit (7 Tage) und – falls vorhanden –
das Opus-Wochenlimit, jeweils mit Reset-Zeit.

- Der OAuth-Token wird aus dem Keychain-Eintrag gelesen, den Claude Code pflegt
  (`Claude Code-credentials`) – kein eigenes Login nötig.
- Abruf nur alle 5 Minuten, da der Endpoint aggressiv ratelimited (sonst HTTP 429).
- Token-Refreshes von Claude Code werden automatisch übernommen (Token wird bei jedem Abruf frisch gelesen).

## Stoppen / Deinstallieren

```bash
launchctl bootout "gui/$(id -u)/com.julian.dynamicisland"   # stoppen + Autostart aus
rm -f ~/Library/LaunchAgents/com.julian.dynamicisland.plist
rm -rf ~/Applications/DynamicIsland.app
```

## Architektur

- `Sources/SpotifyMonitor.swift` – pollt Spotify/Chrome via AppleScript, lädt Cover.
- `Sources/ClaudeUsageMonitor.swift` – berechnet das rollende 5h-Usage-Limit aus den lokalen JSONL-Logs.
- `Sources/NotchWindow.swift` – randloses, klick-durchlässiges Floating-Panel rund um die Notch + Hover-Logik.
- `Sources/IslandView.swift` – SwiftUI-Darstellung (collapsed/expanded mit Spring-Animation).
- `Sources/AppDelegate.swift` / `main.swift` – Agent-App (`LSUIElement`), Single-Instance, Reposition bei Display-Wechsel.
