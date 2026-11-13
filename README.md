# PL DEV

A native iPhone app, built from SwiftUI, that holds many small sections behind one home screen. It comes with a widget, a share sheet extension and a Safari toolbar button; each of those only drops items into a shared inbox on the phone, and the app sends them the next time it opens.

This repository holds the app's code only. It holds no keys, addresses or accounts.

## The config file

Everything private arrives at run time from one config file. You load it once (the app's first screen asks for it, or open a `.json` file into the app from Files). The app checks it, keeps it in the Keychain, and makes no network request before it is loaded. The extensions only ever see a copy with the keys removed.

An example with made-up values:

```json
{
  "v": 1,
  "sections": ["status"],
  "origins": {
    "cron": {
      "base": "https://example.com/",
      "auth": { "key": "widgetRead", "header": "Authorization", "scheme": "Bearer" }
    }
  },
  "keys": {
    "widgetRead": "KEY-PLACEHOLDER"
  }
}
```

- `v` must be `1`.
- `sections` is the order of the home grid.
- Each origin's `base` must start with `https://`. `auth.key` names an entry in `keys`.
- Name your real file `pldev-config.json`: git ignores that name here, so it cannot be committed by accident.

## Builds

1. Every push runs the `logic` workflow on Linux: the tests of the plain logic in `PLDevCore`, a structural check of the Xcode project file, and a scan that fails if anything private is in the tree or the history.
2. The `build` workflow is started by hand from the Actions tab. It builds the app unsigned on a Mac runner, checks the three extensions are inside it, and publishes `PLDev.ipa` with a `source.json` as a release named `build-N`.
3. The app is signed on the phone when it is installed.

The app icon and the Safari toolbar icons are placeholders drawn by `scripts/make_icons.py`.
