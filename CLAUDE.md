# PhotoEditor

iOS photo editor (SwiftUI + Core Image + SwiftData). Built and deployed entirely from Linux — no Mac required.

## Build & Deploy Pipeline

The full pipeline: edit on Linux → push to GitHub → macOS CI builds + signs → download `.ipa` → install to iPhone over USB.

### Repo
- GitHub: `Cels000/PhotoEditor` (public — gives unlimited free macOS Actions minutes).
- Workflow: `.github/workflows/ios-build.yml` runs on every push to `main` and on manual dispatch.

### Signing assets (stored as GitHub Actions secrets)
| Secret | Source |
|---|---|
| `APPLE_TEAM_ID` | `WLPV78FA7W` (developer.apple.com → Membership) |
| `BUILD_CERTIFICATE_BASE64` | `base64 -w0 ios_dev.p12` — Apple Development cert |
| `P12_PASSWORD` | Password chosen during `.p12` export |
| `BUILD_PROVISION_PROFILE_BASE64` | `base64 -w0 PhotoEditor_Development.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Random; only used inside CI keychain |

Bundle ID: `com.cels000.PhotoEditor`. Profile name: `PhotoEditor Development` (must match exactly in workflow `env`).

### CI workflow stages (`.github/workflows/ios-build.yml`)
1. **Import signing assets** — decode base64 secrets into a temp keychain; install profile under `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`. UUID is extracted via `security cms -D` → `PlistBuddy` (must use a temp file, not `/dev/stdin`).
2. **Archive** — `xcodebuild archive` with manual signing flags (`CODE_SIGN_STYLE=Manual`, `PROVISIONING_PROFILE_SPECIFIER`, `CODE_SIGN_IDENTITY="Apple Development"`).
3. **Export IPA** — `xcodebuild -exportArchive` with an inline `ExportOptions.plist` (method=`development`, signingStyle=`manual`).
4. **Upload artifact** — `PhotoEditor-ipa` containing the `.ipa`.

### Download + install (Linux side)
```bash
cd ~/Downloads
rm -f PhotoEditor.ipa
gh run download --name PhotoEditor-ipa --repo Cels000/PhotoEditor
ideviceinstaller -i PhotoEditor.ipa
```
- Requires `libimobiledevice` + `usbmuxd` (in distro) and `ideviceinstaller` (AUR on Arch/CachyOS).
- iPhone must be plugged in and trusted (`idevicepair pair` if needed).
- iOS 16+ requires **Developer Mode** (Settings → Privacy & Security → Developer Mode) for sideloaded dev-signed apps. One-time toggle; survives reboots.

### Iteration loop
```bash
# edit code, then:
git add -A && git commit -m "..." && git push
gh run watch
cd ~/Downloads && rm -f PhotoEditor.ipa
gh run download --name PhotoEditor-ipa --repo Cels000/PhotoEditor
ideviceinstaller -i PhotoEditor.ipa
```

### Post-push helper for Claude (mandatory)

**The run id changes on every push.** Never reuse a previous block. After every
`git push`, do this exact 3-step routine:

**Step 1 — fetch the actual run id Claude just triggered:**

```bash
gh run list --repo Cels000/PhotoEditor --limit 1 --json databaseId --jq '.[0].databaseId'
```

(Claude calls this via Bash. The result is a number like `25297367461`.)

**Step 2 — paste a copy-pasteable block to the user with that id substituted
into ALL THREE spots:**

```bash
gh run watch <RUN_ID> --repo Cels000/PhotoEditor && \
cd ~/Downloads && rm -f PhotoEditor*.ipa && \
gh run download <RUN_ID> --name PhotoEditor-ipa --repo Cels000/PhotoEditor && \
ideviceinstaller -i PhotoEditor.ipa
```

The `&&` chain runs the whole thing as one command — `gh run watch` blocks
until the run completes, then download + install run only on success.

**Step 3 — never substitute a stale id.** If Claude is uncertain whether the
push triggered a fresh run (e.g., docs-only changes that the user thinks
shouldn't trigger CI but the workflow runs on every push to main), re-run
Step 1. Always confirm against the latest entry in `gh run list`.

**Why this matters:** the user has no Mac and depends on this exact pipeline.
A wrong run id → wrong IPA → confusing test results that look like code bugs
but are stale-build artifacts. Always fetch fresh, always paste fresh.

### Renewal
- **Provisioning profile**: ~1 year. Regenerate at developer.apple.com/profiles, re-base64 into `BUILD_PROVISION_PROFILE_BASE64`.
- **Apple Development cert**: 1 year. Regenerate via OpenSSL CSR flow, re-export `.p12`, re-base64 into `BUILD_CERTIFICATE_BASE64` (and update `P12_PASSWORD` if changed).
- **New device**: register UDID at developer.apple.com/devices, regenerate profile, update secret.

## Project Structure

- `PhotoEditor/` — SwiftUI app sources (`PhotoEditorApp.swift`, `ContentView.swift`, view models, stores, themes).
- `PhotoEditor.xcodeproj/` — Xcode project. Bundle ID and Team ID are hardcoded in `project.pbxproj`; CI overrides via `xcodebuild` flags but local builds use these values.
- `.github/workflows/ios-build.yml` — CI build pipeline.

## Code Conventions

- Targeting iOS 17+ (Swift Charts, `@Observable`, latest PhotosPicker).
- `@MainActor` on view models; CIContext rendering kept on main thread (downsampled to ≤2048px on import).
- Render scheduling uses a single `Task` with 30ms debounce + cancellation; `nonisolated` static render function avoids actor-hop overhead.
- Image processing pipeline is pure (no I/O) — testable in isolation.

## Gotchas

- `xcodebuild` exit code 65 = build/sign failure; check `gh run view <id> --log-failed`.
- `Cannot parse a NULL or zero-length data` in CI = piping `security cms -D` straight into `PlistBuddy /dev/stdin` fails on macos-14 runners. Always write to a temp `.plist` file first.
- Profile **name** mismatch (workflow `PROFILE_NAME` env vs developer portal) silently picks the wrong profile and surfaces as cryptic codesign errors.
- `ideviceinstaller` warnings about `iTunesMetadata.plist` / `.sinf` are harmless — those files only exist for App Store builds.
