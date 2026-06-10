# Deploying PLO Capture (web PWA)

**Live site:** https://geoff24zimmer-coder.github.io/plo-capture/

The app is a Flutter **web** build published to **GitHub Pages** by a GitHub
Actions workflow (`.github/workflows/deploy.yml`). Every push to `main`
rebuilds and redeploys automatically (~2 min).

---

## Re-deploy (the normal case)

```bash
cd ~/HandHistory
# make your changes, then:
git add -A
git commit -m "describe the change"
git push
```

Watch progress in the repo's **Actions** tab. When the `deploy` job goes
green, the live URL above is updated. The browser may keep the old service
worker for a few seconds — a hard refresh (or reopening the installed app)
picks up the new version.

---

## Install on a phone

Open the live URL in **mobile Safari (iOS)** or **Chrome (Android)** →
**Share / ⋮ → Add to Home Screen**. It launches full-screen with a dark
splash. Hands persist in the browser's IndexedDB **on that device** (no
cross-device sync yet).

---

## Local development

Flutter is installed at `~/flutter` (no system install, no Android SDK).

```bash
export PATH="$HOME/flutter/bin:$PATH"   # or prefix ~/flutter/bin/
cd ~/HandHistory/plo-app

flutter run -d chrome     # dev with hot reload
flutter test              # engine test suite
flutter analyze           # lints
flutter build web         # produces build/web/ (static files)
```

To preview a production build locally:

```bash
cd build/web && python3 -m http.server 8000   # then open http://localhost:8000
```

---

## One-time setup (already done — for reference)

- **Repo created** on GitHub, `main` branch, public.
- **GitHub Pages enabled** with **Source: GitHub Actions**
  (Settings → Pages → Build and deployment → Source).
  *If a fresh fork/clone ever errors on the `configure-pages` step with
  "Resource not accessible by integration", this toggle is why — set it, then
  re-run the failed job.*
- **Push auth:** a classic Personal Access Token with **`repo` + `workflow`**
  scopes (the `workflow` scope is required because the repo contains a
  workflow file).

---

## How the build is wired

- The workflow builds with `--base-href "/<repo-name>/"` because GitHub
  **project** Pages serve under a sub-path. Wrong base-href = blank screen /
  404'd assets. The repo name is read automatically, so renaming the repo
  just works.
- Browser storage uses `sqflite_common_ffi_web` (IndexedDB + sqlite3 wasm).
  The worker + wasm assets (`web/sqflite_sw.js`, `web/sqlite3.wasm`) are
  **committed** so any checkout builds without extra steps. If you bump the
  `sqflite_common_ffi_web` version, regenerate them:

  ```bash
  cd ~/HandHistory/plo-app
  flutter pub get
  dart run sqflite_common_ffi_web:setup
  git add web/sqflite_sw.js web/sqlite3.wasm pubspec.lock && git commit -m "bump web db assets"
  ```

## Notes / limitations

- **Web-only target.** `lib/main.dart` imports the web DB package directly, so
  native (Android/iOS) builds are intentionally not supported. Adding native
  back would need a conditional import guard around that one line.
- **Data is per-device** (IndexedDB). Cross-device sync is a future cloud
  layer (see the roadmap in `CLAUDE.md`).
