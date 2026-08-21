# PinDock

Pin the macOS Dock to the display you choose.

Private commercial project. Source and releases are not public.

## Local install

```bash
chmod +x Scripts/*.sh
./Scripts/install.sh
```

→ `/Applications/PinDock.app`

Then **System Settings → Privacy & Security → Accessibility** → enable **PinDock**.

```bash
./Scripts/package_app.sh   # → PinDock.app
./Scripts/package_zip.sh   # → PinDock-x.y.z.zip
```

## Usage

1. Click the pin in the menu bar (or open the app window)
2. **Set as default** on your home display
3. The Dock stays put
4. **⇧ Shift** + bottom edge of an allowed display to move it
5. **⌘⇧D** or **Move Back** when you want it home

## Requirements

- macOS 13+
- Accessibility permission

## License

Proprietary. All rights reserved. See [LICENSE](LICENSE).
