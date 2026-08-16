# Project settings

Scaffolding values for `Patchly.xcodeproj`, generated once via `xcodegen` from `project.yml` and then committed as a plain project.

## Identity

- Bundle ID: `com.mberrish.Patchly`
- Product: macOS app, deployment target macOS 26.0, `arm64` only
- Marketing version `0.1.0`, build `1`
- Category: `public.app-category.utilities`

## Info.plist keys that matter

- `LSUIElement` = true (menu-bar-only, no Dock icon)
- `NSPrincipalClass` = `NSApplication`
- No usage-description keys needed — Patchly never touches microphone, camera, contacts, or any TCC-gated resource; reading other apps' `Info.plist` and shelling out to `brew`/`mas` need no Info.plist permission strings
- `SUFeedURL` = `https://raw.githubusercontent.com/mberrishdev/Patchly/main/appcast.xml` — Patchly's own signed release feed, fetched by the linked Sparkle framework (see `appcast.xml` at the repo root)
- `SUPublicEDKey` = the EdDSA public key from `scripts/generate-sparkle-keys.sh`; must be valid base64 or Sparkle refuses to start ("The updater failed to start")
- `SUEnableAutomaticChecks` = true (default; user-toggleable in Settings via `AppUpdater.automaticallyChecksForUpdates`)

## Entitlements (`Patchly.entitlements`)

Empty. App Sandbox off (`ENABLE_APP_SANDBOX = NO`) — required to shell out to `brew`/`mas` and read other apps' bundles freely. Hardened Runtime on (for eventual notarization). No special entitlements — outbound network for Sparkle feed fetches needs none when unsandboxed.

## Build settings

Base: `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `DEAD_CODE_STRIPPING = YES`, `ONLY_ACTIVE_ARCH = NO`.

Debug signing: Apple Development, automatic. Release signing (Developer ID Application) deferred until distribution is actually planned — not needed for local dev/run.
