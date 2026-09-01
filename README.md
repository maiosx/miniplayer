# MiniPlayer

Small Omarchy/Quickshell media panel that stays pinned to the top-right of the screen.

## Features

- Pin local images, GIFs, and videos
- Animated GIF playback
- MP4/MKV/WebM looping playback
- Video audio is muted until the pointer hovers the video
- Persistent pinned-media list in `~/.config/omarchy/miniplayer.json`
- Toggle from the Omarchy shell/bar widget
- Minimal translucent UI

## Install

```sh
plugin add https://github.com/maiosx/miniplayer.git
```

Then toggle it with the Omarchy plugin shell integration:

```sh
omarchy-shell shell toggle miniplayer
```

## Notes

Video playback uses Qt Multimedia, so the available codecs depend on the Qt multimedia backend installed by the system.

MIT License.
