# Maintainer notes

PinDock is a **private commercial** app. The GitHub repo is private and must stay private.

## Branch policy

| Branch | Purpose |
|--------|---------|
| **`dev`** | Active work (local, default) |
| **`main`** | Stable snapshots — only after explicit acceptance |

New work stays on **`dev`**. Do not make the repository public.

## Releases

Paid distribution is not wired yet. Until then:

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`
2. Merge accepted work to **`main`** only when asked
3. `./Scripts/package_zip.sh` for a local ZIP

Do not publish public GitHub Releases.

## Please don’t

- Change visibility back to public
- Restore an MIT license on new versions
- Push unless explicitly asked
