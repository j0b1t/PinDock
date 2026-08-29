# Contributing

PinDock is open source (MIT) for **use and study**. External contributions are **by invitation only**.

## Branch policy (maintainer)

| Branch | Visibility | Purpose |
|--------|------------|---------|
| **`main`** | Public (GitHub) | Stable releases only |
| **`dev`** | Local / not published | Active development until accepted |

New work stays on **`dev`**. It is merged to **`main`** only after explicit acceptance.  
**`dev` is not pushed** to the public repository (GitHub cannot hide a branch on a public repo).

## Release policy (maintainer)

Every **new version** on `main` must ship as a **GitHub Release** (tag `vX.Y.Z` + `PinDock-X.Y.Z.zip`):

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`
2. Merge accepted work to **`main`** and push
3. Run `./Scripts/release.sh` (or `./Scripts/release.sh X.Y.Z`)

Do **not** leave version bumps on `main` without a corresponding public release.

README shots + GIFs: `./Scripts/install.sh && ./Scripts/capture_screenshots.sh`  
(real menu-bar bubble with arrow, app window, walkthrough GIFs).

## Please do

- Open an **issue** for clear bugs (macOS version, display layout, Dock position).  
- Fork and modify for yourself under the MIT license.

## Please don’t

- Open pull requests without a prior, explicit invitation from the maintainer.  
- Expect reviews of drive‑by patches or feature PRs.  
- Treat `main` as a working branch.

Unsolicited pull requests may be closed without comment.
