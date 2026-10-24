# GodotSteam runtime dependency

GodotSteam 4.23.2 GDExtension, from the official release:
https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.23.2-gde

Installed from `godotsteam-4.23.2-gdextension-plugin-4.4.zip`.
Archive SHA-256: `4f1db786924ad0e1de9b161d87276b1a0b7504332ceec2e9c6694be202c33da4`.
This project bundles the Windows x86-64 debug/release libraries and Steam API redistributable. Other platforms require the corresponding libraries from that release. The original extension descriptor and MIT license are retained.

This is a runtime extension. The optional GodotSteam editor updater/plugin is not enabled or required. Steam initialization and callbacks are owned by `src/network/steam_online.gd`.
