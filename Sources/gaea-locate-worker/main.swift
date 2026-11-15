import GaeaPluginKit
import LocatePlugin

// The plugin's worker: LocatePlugin's definition over GPP (GaeaPluginKit). `--manifest <path>` writes manifest.json.
await GaeaPluginMain.run(locatePlugin)
