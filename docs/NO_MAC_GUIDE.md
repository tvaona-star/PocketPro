# Running Pocket Pro with no Mac — Windows PC + iPhone only

You don't need to own a Mac. A free GitHub Actions runner *is* your Mac: it compiles
the app, runs the full test suite, and produces an installable `.ipa`. Your Windows
PC then sideloads that `.ipa` onto your iPhone. Two routes, depending on whether you
want to spend money:

| | Route A — Free | Route B — $99/yr Apple Developer |
|---|---|---|
| Install method | AltStore sideload via Windows | TestFlight (over the air) |
| App expires | Every 7 days (one-tap refresh) | 90 days per build, auto-updates |
| App limit | 3 sideloaded apps | none |
| iCloud sync (CloudKit) | ❌ not available | ✅ works |
| Push notifications | ❌ | ✅ |
| Share with friends/testers | ❌ | ✅ up to 10,000 testers |
| App Store release | ❌ | ✅ |

**Recommendation:** start with Route A today (zero cost, ~30 minutes of setup),
upgrade to Route B when the app proves itself — nothing about the project changes.

---

## Step 1 — Put the project on GitHub (one-time, ~5 min)

The repo is already committed locally. You need a GitHub account (free — private
repos include 2,000 CI minutes/month; **public repos get unlimited free macOS
minutes**, and there's nothing secret in this codebase).

The easy way, from PowerShell in the project folder:

```powershell
# One-time: authenticate the GitHub CLI (opens your browser)
gh auth login

# Create the repo and push in one shot (pick --public for unlimited CI minutes)
gh repo create PocketPro --public --source . --push
```

That's it. The push automatically triggers the CI workflow
(`.github/workflows/ios.yml`).

> Claude can drive everything after `gh auth login` — creating the repo, pushing,
> reading build errors, fixing them, and re-pushing until the build is green.

## Step 2 — Let CI build it

On github.com → your repo → **Actions** tab. Each push runs three jobs:

1. **Core engine tests** — the full XCTest suite (classifier, scoring, stats, import).
2. **Build app + unsigned IPA** — full compile of the SwiftUI app, then uploads
   `PocketPro-unsigned-ipa` as a downloadable artifact.
3. **Simulator build** — Debug-configuration compile check.

First builds of hand-written-on-Windows Swift usually need a few fix iterations —
that's the loop Claude runs for you: read the error log, fix, push, repeat.
Once green, every future push gives you a fresh `.ipa` in ~10 minutes.

## Step 3 (Route A) — Sideload with AltStore from Windows (one-time setup ~20 min)

AltServer is a small Windows tray app that signs apps with a **free** Apple ID and
installs them on your iPhone.

1. Install **iTunes** and **iCloud** from Apple's website (AltStore's FAQ covers the
   Microsoft-Store-version caveats if pairing fails: altstore.io/faq).
2. Download **AltServer for Windows** from [altstore.io](https://altstore.io) and run it
   (it lives in the system tray).
3. Connect your iPhone by USB cable, tap **Trust** on the phone.
4. Tray icon → **Install AltStore** → pick your iPhone → enter your Apple ID.
   (Use a throwaway/secondary free Apple ID if you prefer — it's only for signing.)
5. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID
   profile. The AltStore app now works.
6. Download `PocketPro-unsigned-ipa` from the GitHub Actions run (it downloads as a
   `.zip` — extract it to get `PocketPro-unsigned.ipa`).
7. AltServer tray icon → **Sideload .ipa** → choose the file → pick your iPhone.
   Pocket Pro appears on your home screen.

**The 7-day rule:** free-Apple-ID apps expire weekly. Open the AltStore app on your
phone (same Wi-Fi as the PC running AltServer) and tap **Refresh All** — takes
seconds. Do it whenever you think of it; data is never lost on expiry, the app
just won't launch until refreshed.

**Updating to a new build:** download the new `.ipa`, sideload again — it installs
over the top, keeping all your data.

## Step 3 (Route B) — TestFlight instead (when you have the $99 account)

1. Enroll at developer.apple.com ($99/yr — works fine from Windows; it's a website).
2. Create an **App Store Connect API key** (App Store Connect → Users and Access →
   Integrations → App Store Connect API → Team key, role: App Manager). Note the
   Key ID + Issuer ID, download the `.p8` once.
3. Add three GitHub repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`
   (the file's contents).
4. Tell Claude — a `release.yml` workflow gets added that builds a **signed** archive
   in CI (cloud-managed signing via the API key), uploads it to TestFlight, and your
   iPhone gets it through the TestFlight app like any normal beta. This is also the
   moment to flip on iCloud sync (docs/CLOUDKIT.md) since paid accounts have CloudKit.

## Day-to-day workflow

```
edit code on Windows (with Claude)
  → run PowerShell reference tests locally (instant)
  → git push
  → GitHub Actions compiles + tests on macOS (~10 min)
  → green: download .ipa → sideload → bowl with it
  → red: Claude reads the log, fixes, pushes again
```

## FAQ

- **Is sideloading safe/allowed?** Yes — AltStore uses Apple's own free developer
  provisioning, the same mechanism Xcode uses for personal devices. Nothing is
  jailbroken.
- **Why is CloudKit off in Route A?** Free Apple IDs can't create iCloud containers.
  The app is built local-first; sync turns on with config only (docs/CLOUDKIT.md).
- **Can I avoid the PC for weekly refreshes?** Look at **SideStore** (a community
  AltStore fork) — after a one-time setup it refreshes on-device. Slightly more
  involved install; start with AltStore.
- **MacinCloud etc.?** Renting a cloud Mac (~$30/mo) only adds value if you want to
  click around Xcode yourself. For build/test/distribute, CI does it free.
