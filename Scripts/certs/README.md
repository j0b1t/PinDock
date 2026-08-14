# Local signing (generated on your machine)

`ensure_signing_identity.sh` creates:

| File | Purpose | In git? |
|------|---------|---------|
| `PinDockDevelopment.p12` | Private key + cert | **No** |
| `PinDock.keychain-db` | Dedicated keychain for codesign | **No** |
| `PinDockDevelopment.cer` | Public cert only (optional) | optional |

These keep a **stable codesign identity** so Accessibility survives app updates under `/Applications/PinDock.app`.

Never commit `.p12` or `.keychain-db`.
