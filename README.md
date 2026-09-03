# MiniPlayer
<img width="1092" height="716" alt="Preview" src="Preview.png" />

Small Omarchy/Quickshell media panel that stays pinned to the top-right of the screen.

## Features

- Drag and drop support
- Pin local images, GIFs, and videos
- Animated GIF playback
- MP4/MKV/WebM looping playback
- Video audio is muted until the pointer hovers the video
- Persistent pinned-media list in `~/.config/omarchy/miniplayer.json`
- Minimal translucent UI
- Fullscreen Toggle

## Install

```sh
omarchy plugin add https://github.com/maiosx/miniplayer.git --enable
```

`omarchy plugin add` on its own only clones the plugin — it lands **disabled**, so the bar icon won't appear until you enable it. If you already installed it without `--enable`, run:

```sh
omarchy plugin enable miniplayer
```

(and, if prompted, pick which bar section to place it in — it defaults to `right`). You can confirm it's active with `omarchy plugin list`.

Suggested keybind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + X", "miniplayer", "omarchy-shell shell toggle miniplayer")
```

Or toggle it with the Omarchy plugin shell integration:

```sh
omarchy-shell shell toggle miniplayer
```
## Remove

```sh
omarchy plugin remove miniplayer
```
## Notes

Video playback uses Qt Multimedia, so the available codecs depend on the Qt multimedia backend installed by the system.

MIT License.
