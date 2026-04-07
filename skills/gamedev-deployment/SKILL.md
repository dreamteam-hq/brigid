---
name: gamedev-deployment
description: >
  Game export, platform deployment, and live ops — Godot export presets for PC,
  mobile, web, and headless server; Steam integration via Steamworks SDK;
  CI/CD build pipelines with GitHub Actions; patching and delta updates;
  live operations including analytics, A/B testing, and season systems.
  Load when the user mentions "game export", "game deployment", "Steam integration",
  "Steamworks", "game CI/CD", "game build pipeline", "game patching", "live ops",
  "game analytics", "Godot export", "export presets", "delta patching",
  "version stamping", or "season system".
triggers:
  - game export
  - game deployment
  - Steam integration
  - Steamworks
  - game CI/CD
  - game build pipeline
  - game patching
  - live ops
  - game analytics
  - Godot export
version: "1.0.0"
---

# Game Deployment and Live Operations

Export Godot projects to every major platform, integrate with Steam, automate builds with CI/CD, ship patches efficiently, and run live operations post-launch. This skill covers the full pipeline from "it works in the editor" to "players are playing it in production."

## Decision Framework

Before setting up your deployment pipeline, resolve these architectural choices.

### Target Platform Matrix

| Platform | Export Template | Distribution | Key Constraints |
|----------|----------------|--------------|-----------------|
| Windows | `windows_desktop` | Steam, Epic, itch.io, direct | Code signing required for SmartScreen |
| Linux | `linux_x11` | Steam, itch.io, Flatpak, direct | Test on SteamOS/Deck explicitly |
| macOS | `macos` | Steam, App Store, direct | Notarization mandatory, universal binary (x86_64+arm64) |
| Web | `web` | itch.io, self-hosted | SharedArrayBuffer requires COOP/COEP headers |
| Android | `android` | Google Play, sideload | AAB required for Play Store, target API level compliance |
| iOS | `ios` | App Store | Xcode required for final archive, provisioning profiles |
| Headless server | `linux_x11` (headless) | Docker, bare metal, cloud VMs | No GPU, strip rendering, minimal export |

Choose your tier-1 platforms early. Each platform you support multiplies QA surface area. Most indie games ship Windows + Linux (Steam) first, then expand.

### Distribution Channel Selection

| Channel | Revenue Split | Update Model | DRM | Best For |
|---------|--------------|--------------|-----|----------|
| Steam | 70/30 (75/25 at $10M, 80/20 at $50M) | Built-in delta patching | Optional (Steamworks DRM) | PC games, largest audience |
| Epic Games Store | 88/12 | Built-in | Epic Online Services | Exclusivity deals, UE games |
| itch.io | 0-100% (creator sets) | Butler push | None | Indies, game jams, early builds |
| Google Play | 70/30 (85/15 under $1M) | Built-in | Play Integrity | Android mobile |
| Apple App Store | 70/30 (85/15 under $1M) | Built-in | FairPlay | iOS mobile |
| Self-hosted | 100/0 | Custom | Custom | Niche, enterprise, private |

### Versioning Strategy

Use semantic versioning with a build number: `MAJOR.MINOR.PATCH+BUILD`. Encode this into the binary at build time so it is queryable at runtime and in crash reports.

- **MAJOR**: Breaking save compatibility, protocol version bump
- **MINOR**: New content, features, non-breaking changes
- **PATCH**: Bug fixes, balance tweaks
- **BUILD**: Auto-incremented by CI, monotonically increasing

Store the version in a project-level autoload so every system can query it. See [references/gdscript-implementations.md](references/gdscript-implementations.md) for the `version.gd` autoload implementation.

## Godot Export Presets

Export presets live in `export_presets.cfg` at the project root. Each preset defines the target platform, included/excluded resources, feature tags, and platform-specific options. Commit this file to version control.

See [references/ci-cd-workflows.md](references/ci-cd-workflows.md) for full `.ini` preset blocks for all platforms.

### PC (Windows / Linux / macOS)

For Windows: always set `file_version` and `product_version` for crash report correlation. Enable code signing to avoid SmartScreen warnings — unsigned executables trigger "Windows protected your PC" dialogs that tank conversion.

For macOS: export as universal binary (`universal`), set the bundle identifier, and notarize. Without notarization, macOS Sequoia+ blocks the app entirely. Use `rcodesign` in CI for notarization without a Mac.

For Linux: export as x86_64. Test on Steam Deck (SteamOS) — it runs a modified Arch Linux with Proton, but native Linux builds avoid Proton overhead and controller mapping issues.

### Web Export

Web exports require specific HTTP headers to enable SharedArrayBuffer (needed for threading):

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Without these headers, the game falls back to single-threaded mode. Configure in your web server (nginx, Caddy, Cloudflare Pages `_headers` file). For itch.io, enable SharedArrayBuffer in the project settings.

### Mobile Export (Android / iOS)

For Android, export as AAB (Android App Bundle) for Play Store submission. Sign AABs with a keystore — use a separate debug keystore for development and a release keystore stored securely (not in the repo). Google Play App Signing manages upload key rotation.

For iOS: export the Xcode project, then archive and submit from Xcode or via `xcodebuild` in CI. Provisioning profiles and certificates must be available in the CI environment (use match or Fastlane).

### Headless Server Export

Export a stripped-down build for dedicated servers. Run headless with `--headless` flag. Strip all rendering assets (sprites, audio, shaders, UI textures) to minimize image size. A well-stripped headless export can be 10-50MB versus 500MB+ for a full client.

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 \
    && rm -rf /var/lib/apt/lists/*
COPY build/server/game-server /opt/game/
WORKDIR /opt/game
EXPOSE 7777/udp 7778/tcp
ENTRYPOINT ["./game-server", "--headless", "--", "--server-mode"]
```

## Steam Integration

Use GodotSteam (the most mature Godot-Steam binding) or the official Steamworks GDExtension. GodotSteam provides pre-compiled editor and export templates with Steamworks baked in.

Setup steps:

1. Download GodotSteam-compiled templates from the release page
2. Place `steam_appid.txt` containing your app ID in the project root (for dev only — Steam removes this requirement when launched through the client)
3. Initialize Steam in an autoload — always call `Steam.run_callbacks()` every frame. Missing this causes achievements, overlay, and networking callbacks to silently fail.

For achievements: define them in the Steamworks partner dashboard first. Batch `storeStats()` calls — do not call it every frame. Once per achievement unlock or at natural save points.

For cloud saves: configure storage quota in Steamworks partner settings (default 1GB per user per game). Use compact save formats (binary, not JSON). Handle cloud conflicts — Steam raises a conflict callback when local and remote saves diverge.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for `steam_manager.gd`, achievements, cloud saves, and Workshop upload implementations.

## Build Pipelines

### GitHub Actions CI/CD

Automate Godot exports with GitHub Actions. Use `chickensoft-games/setup-godot` for Godot installation and a matrix build across platforms. Gate exports on test passage — never ship a build that fails tests.

Key steps in the pipeline:
1. Determine version from tag or workflow input
2. Stamp version constants into source via `sed` before export
3. Run `godot --headless --import` to process assets
4. Export each platform with `godot --headless --export-release`
5. Deploy to Steam via `game-ci/steam-deploy@v3`, itch.io via butler

See [references/ci-cd-workflows.md](references/ci-cd-workflows.md) for the complete GitHub Actions workflow YAML and test step.

### Version Stamping

CI stamps version constants into `version.gd` before export via `sed`. This ensures the in-game version display matches the git tag, crash reports include the exact build number, multiplayer protocol checks can reject incompatible clients, and Steam depot descriptions are traceable to git commits.

For more advanced stamping, generate a `build_info.tres` resource file at build time. See [references/ci-cd-workflows.md](references/ci-cd-workflows.md) for the template.

## Patching and Updates

### Asset Bundles

For games with large asset libraries (200MB+), separate code and assets to enable smaller patches:

```
game/
├── game.pck          # Core game code + essential assets (~50MB)
├── assets_base.pck   # Base content pack (~400MB)
├── assets_dlc1.pck   # DLC content (~200MB)
└── assets_event.pck  # Seasonal event assets (~100MB)
```

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for the `load_asset_pack` function.

### Delta Patching

Steam handles delta patching automatically through its depot system. For non-Steam distribution, implement your own:

1. **Generate patch manifests** at build time: hash every file in the build, store as JSON
2. **Diff manifests** between versions: identify added, removed, and changed files
3. **Distribute only changed files**: download changed files, apply locally

For binary delta patching (bsdiff/xdelta), generate patches between old and new versions of large files. A 500MB asset that changes 2% of its data produces a ~10MB delta patch instead of a 500MB re-download.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for `patch_checker.gd`.

### Client/Server Version Compatibility

For multiplayer games, version mismatches cause desyncs, crashes, or exploits. Implement protocol versioning with a handshake on connection.

| Scenario | Action |
|----------|--------|
| Same protocol version | Allow connection |
| Different protocol, same major | Warn, allow with feature negotiation |
| Different major version | Reject connection, prompt update |
| Server newer than minimum | Allow |
| Client below minimum build | Reject, force update |

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for the version handshake implementation.

## Live Operations

### Server Monitoring

Expose a Prometheus-compatible metrics endpoint from dedicated servers. Use Prometheus + Grafana for dashboards. Set up PagerDuty or Opsgenie alerts for critical thresholds. For small teams, Grafana Cloud free tier handles most indie game server monitoring needs.

Key metrics to track:

| Metric | Type | Alert Threshold |
|--------|------|----------------|
| Players online | Gauge | N/A (capacity planning) |
| Tick duration | Gauge | >80% of tick budget |
| Tick overruns | Counter | >1% of ticks |
| Network bytes sent/received | Counter | Sudden spikes |
| Active matches | Gauge | Near capacity |
| Memory usage | Gauge | >80% of container limit |
| Error rate | Counter | >0.1% of requests |
| Player disconnection rate | Gauge | >5% in 5 minutes |

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for the `metrics_server.gd` Prometheus endpoint.

### Player Analytics

Track gameplay events for balancing and retention analysis. Batch events and flush every 30 seconds. For GDPR/CCPA compliance: obtain consent before tracking, provide data export and deletion, anonymize player IDs in analytics pipelines.

Essential events to track:

| Event | Properties | Purpose |
|-------|-----------|---------|
| `session_start` | platform, version, locale | DAU/MAU, version adoption |
| `session_end` | duration, reason | Session length distribution |
| `level_start` | level_id, difficulty | Funnel analysis |
| `level_complete` | level_id, duration, deaths, score | Difficulty tuning |
| `level_abandon` | level_id, time_played, last_checkpoint | Churn identification |
| `purchase` | item_id, currency_type, amount | Economy health |
| `achievement_unlock` | achievement_id, time_played | Progression pacing |
| `error` | error_type, stack_trace, scene | Crash prioritization |

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for `analytics.gd`.

### A/B Testing

Use deterministic hashing (player_id + experiment_name) for consistent variant assignment — players always see the same variant without server-side state.

Common A/B tests for games:

| Experiment | Variants | Metric |
|-----------|----------|--------|
| Tutorial length | Short / Standard / Extended | D1 retention |
| Starting currency | 100 / 500 / 1000 | D7 spend rate |
| Difficulty curve | Gentle / Standard / Steep | Level 5 completion rate |
| Shop layout | Grid / List / Featured | Conversion rate |
| Reward frequency | Every level / Every 3 / Every 5 | Session length |

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for `feature_flags.gd`.

### Event and Season Systems

Season system design principles:

- **Server-authoritative timing**: Never trust the client clock for event start/end. Fetch timestamps from the server.
- **Graceful degradation**: If the config server is unreachable, fall back to cached config or a baked-in default season.
- **Content pre-loading**: Download seasonal assets before the event starts. Use analytics to track download completion rates.
- **FOMO balance**: Make seasonal rewards cosmetic or convenience, not power. Players who miss a season should not be mechanically disadvantaged.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for `season_manager.gd`.

## Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|-------------|---------|-----------------|
| No version stamping | Cannot correlate crash reports to builds, players run unknown versions | Stamp version + build number at CI time, embed in binary |
| Manual exports | Human error, inconsistent builds, "works on my machine" | Automated CI/CD with GitHub Actions, deterministic builds |
| Monolithic PCK | Every patch requires full re-download of entire game | Split into code PCK + asset packs, enable delta patching |
| Hardcoded store IDs | Cannot test without real store credentials, no staging | Environment-based configuration, test app IDs for development |
| Client-trusted analytics | Players can spoof events, skewing data | Validate critical events server-side, sanity-check client telemetry |
| No protocol versioning | Version mismatches cause silent desyncs or crashes | Protocol version in handshake, reject incompatible clients |
| Shipping debug exports | Debug builds include console, profiler, slower performance | Separate debug/release presets, CI only ships release |
| No code signing | OS blocks or warns about unsigned executables | Sign Windows (Authenticode), macOS (notarization), Android (keystore) |
| Analytics without consent | GDPR/CCPA violations, store policy rejection | Consent dialog before first track call, honor opt-out |
| Event content in client build | Cannot update events without a full game patch | Remote config + downloadable asset packs for seasonal content |
| Sleep-based update loops | `Thread.Sleep` for tick/update loops causes timing drift | Use precise timing (`Time.get_ticks_msec()` or `Stopwatch`) |
| No graceful shutdown | Server kills disconnect all players immediately, data loss | Drain connections, persist state, broadcast warning before shutdown |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-server-architecture` | Dedicated server design, tick loops, .NET hosting, TCP/UDP networking |
| `gamedev-godot` | Godot editor workflows, scene architecture, GDScript patterns |
| `gamedev-multiplayer` | Client-side networking, state sync, lag compensation |
| `gamedev-ecs` | Entity Component System for server-side game state |
| `gamedev-mmo-persistence` | Database design for persistent worlds, save systems at scale |
| `game-economy-design` | Virtual economy balancing, currency systems, monetization |
