pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Window
import QtMultimedia

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool fullscreenOpen: false
  property int panelTopMargin: 52
  property var mediaItems: []
  property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/omarchy"
  property string configPath: root.configDir + "/miniplayer.json"
  readonly property int maxMediaItems: 200

  // MiniPlayer only ever displays locally-picked or locally-dropped media.
  // Reject anything that isn't a local file:// URL with an EMPTY (or
  // "localhost") authority. A bare "^file://" prefix match is not enough:
  // "file://somehost/share/x.mp4" also matches that prefix, and on Windows
  // Qt resolves a non-empty, non-local host in a file: URL as a UNC path
  // (\\somehost\share\x.mp4), turning a supposedly-local media add into an
  // outbound SMB connection to an attacker-chosen host (NTLM leak vector).
  // Requiring the character right after "file://" to be "/" (empty
  // authority) or "localhost/" closes that off.
  function isAllowedMediaUrl(u) {
    if (typeof u !== "string" || u.length === 0 || u.length > 4096) return false
    if (!/^file:\/\//i.test(u)) return false
    var rest = u.slice(7) // strip the "file://" we just matched
    // Defense in depth: don't let a percent-encoded "//" or "\" smuggle an
    // authority-looking segment past a naive consumer further down the line.
    if (/%2f%2f|%5c/i.test(rest)) return false
    return rest.charAt(0) === "/" || /^localhost\//i.test(rest)
  }

  function toggle() { opened ? dismiss() : open("{}") }
  function open(payload) { opened = true; configFile.reload() }
  function close() { opened = false }
  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "miniplayer")
  }
  function save() {
    configFile.setText(JSON.stringify(root.mediaItems))
  }
  function addMedia(url) {
    if (!root.isAllowedMediaUrl(url)) return
    if (root.mediaItems.indexOf(url) >= 0) return
    if (root.mediaItems.length >= root.maxMediaItems) return
    root.mediaItems = root.mediaItems.concat([url])
    save()
  }
  function removeMedia(index) {
    var a = root.mediaItems.slice()
    a.splice(index, 1)
    root.mediaItems = a
    save()
  }

  IpcHandler {
    target: "miniplayer"
    function toggle(): void { root.toggle() }
    function open(): void { root.open("{}") }
    function close(): void { root.dismiss() }
    function status(): string { return root.opened ? "open" : "closed" }
  }

  // One-shot, narrowly-scoped directory creation. This is the only
  // subprocess left in the file, and it's hardened on both axes the review
  // flagged: the command list is exec'd directly (no "sh -c", so there's no
  // shell metacharacter parsing to worry about even though configDir isn't
  // attacker-controlled), and the environment is cleared and replaced with
  // an explicit, minimal PATH so a hijacked PATH entry inherited from the
  // session can't shadow the mkdir binary.
  Process {
    id: mkdirHelper
    clearEnvironment: true
    environment: ({ PATH: "/usr/bin:/bin" })
    command: ["mkdir", "-p", root.configDir]
  }

  // Config is read/written through FileView rather than a shell pipeline:
  // - nothing here spawns a process, so there's no inherited-environment
  //   subprocess left to sandbox for this path
  // - each operation is a single open() against configPath, not a separate
  //   lstat/stat/size-check followed later by a second open of the same
  //   mutable pathname -- so there's no window between "check" and "use"
  //   for something else to swap the file underneath us
  // - setText() goes through atomicWrites (write to a temp file, rename
  //   over the target), which is the same "write elsewhere, rename into
  //   place" guarantee the old mktemp-based writer provided
  //
  // Trade-off vs. the old reader: this follows a symlink at configPath the
  // same way any normal file access would, rather than refusing to read
  // through one outright -- QML has no O_NOFOLLOW-open primitive to do that
  // race-free, and the old check-then-open version only *looked* like it
  // rejected symlinks while still racing. Given every entry that comes out
  // of this file is re-validated by isAllowedMediaUrl() before it's trusted
  // for anything, that's an acceptable bound for this data path; it isn't
  // an acceptable bound for arbitrary config, so don't reuse this pattern
  // for files whose raw content gets trusted directly.
  FileView {
    id: configFile
    path: root.configPath
    preload: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(configFile.text() || "[]")
        var list = Array.isArray(parsed) ? parsed : []
        var filtered = []
        for (var i = 0; i < list.length && filtered.length < root.maxMediaItems; ++i) {
          if (root.isAllowedMediaUrl(list[i])) filtered.push(list[i])
        }
        root.mediaItems = filtered
      } catch (e) { root.mediaItems = [] }
    }
    // Covers both "file doesn't exist yet" (first run, before any save())
    // and genuine read errors -- either way we fall back to an empty list
    // rather than leaving the panel showing stale/partial data.
    onLoadFailed: (error) => { root.mediaItems = [] }
  }

  Component.onCompleted: mkdirHelper.running = true

  FileDialog {
    id: picker
    title: "Choose media"
    fileMode: FileDialog.OpenFiles
    nameFilters: ["Media (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.mp4 *.mkv *.webm)", "All files (*)"]
    onAccepted: {
      for (var i = 0; i < selectedFiles.length; ++i) root.addMedia(selectedFiles[i].toString())
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    implicitWidth: 420
    implicitHeight: Math.min(700, Math.max(172, 74 + Math.max(1, root.mediaItems.length) * 220))
    anchors.top: true
    anchors.right: true
    margins.top: root.panelTopMargin
    margins.right: 18
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "miniplayer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      radius: 18
      color: "#e6151517"
      border.width: 1
      border.color: "#30ffffff"

      Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Item {
          width: parent.width
          height: 36

          Text {
            text: "MiniPlayer"
            color: "#f5f5f7"
            font.pixelSize: 18
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Button {
              text: "×"
              onClicked: if (!root.fullscreenOpen) root.close()
            }
          }
        }

        Flickable {
          width: parent.width
          height: parent.height - 46
          contentWidth: width
          contentHeight: mediaColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: mediaColumn
            width: parent.width
            spacing: 10

            Text {
              visible: root.mediaItems.length === 0
              text: "Drop a file to add"
              color: "#8e8e93"
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              topPadding: 80
            }

            Repeater {
              model: root.mediaItems
              delegate: Rectangle {
                required property string modelData
                required property int index
                width: mediaColumn.width
                height: 210
                radius: 12
                color: "#121214"
                clip: true

                property bool isVideo: /\.(mp4|mkv|webm|mov)$/i.test(modelData.split("?")[0])
                property bool audioUnlocked: false
                property bool isFullscreen: false
                property bool videoPaused: false
                property int playbackPosition: 0

                function setFullscreen(value) {
                  if (value === isFullscreen) return
                  playbackPosition = isFullscreen ? fullscreenVideo.position : video.position
                  isFullscreen = value
                  root.fullscreenOpen = value
                  root.panelTopMargin = value ? -400 : 52
                  seekTimer.restart()
                }

                Image {
                  id: image
                  anchors.fill: parent
                  source: isVideo ? "" : modelData
                  fillMode: Image.PreserveAspectCrop
                  cache: true
                  asynchronous: true
                  visible: !isVideo
                }

                AnimatedImage {
                  anchors.fill: parent
                  source: (!isVideo && /\.gif$/i.test(modelData.split("?")[0])) ? modelData : ""
                  fillMode: Image.PreserveAspectCrop
                  playing: true
                  visible: !isVideo && /\.gif$/i.test(modelData.split("?")[0])
                }

                Video {
                  id: video
                  anchors.fill: parent
                  source: isVideo && !isFullscreen ? modelData : ""
                  fillMode: VideoOutput.PreserveAspectCrop
                  autoPlay: true
                  loops: MediaPlayer.Infinite
                  muted: isFullscreen || !(videoArea.containsMouse || audioUnlocked)
                  volume: isFullscreen ? 0.0 : ((videoArea.containsMouse || audioUnlocked) ? 1.0 : 0.0)
                  visible: isVideo && !isFullscreen
                  onSourceChanged: {
                    if (videoPaused) pause()
                    seekTimer.restart()
                  }
                }

                SeekBar {
                  id: miniSeekBar
                  visible: isVideo && !isFullscreen && videoArea.containsMouse
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  anchors.bottomMargin: 6
                  position: video.position
                  duration: video.duration
                  onSeekRequested: function(ms) { video.seek(ms) }
                }

                Window {
                  id: fullscreenWindow
                  visible: isFullscreen
                  width: Screen.width
                  height: Screen.height
                  color: "black"
                  flags: Qt.Window | Qt.FramelessWindowHint

                  property bool controlsVisible: true

                  onVisibleChanged: {
                    if (visible) {
                      fullscreenWindow.requestActivate()
                      controlsVisible = true
                      hideControlsTimer.restart()
                    }
                  }

                  Timer {
                    id: hideControlsTimer
                    interval: 3000
                    repeat: false
                    onTriggered: fullscreenWindow.controlsVisible = false
                  }

                  MouseArea {
                    id: activityArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: fullscreenWindow.controlsVisible ? Qt.ArrowCursor : Qt.BlankCursor
                    onPositionChanged: {
                      fullscreenWindow.controlsVisible = true
                      hideControlsTimer.restart()
                    }
                  }

                  // Hyprland's Super+W (killactive) closes the focused window at the
                  // compositor level via a WM close request, not a key event delivered
                  // to the app. Intercept that request instead of letting the window
                  // get destroyed out from under isFullscreen/root.panelTopMargin.
                  onClosing: function(closeEvent) {
                    closeEvent.accepted = false
                    setFullscreen(false)
                  }

                  Shortcut {
                    sequence: "Escape"
                    onActivated: setFullscreen(false)
                  }

                  Shortcut {
                    sequence: "Meta+W"
                    onActivated: setFullscreen(false)
                  }

                  Video {
                    id: fullscreenVideo
                    anchors.fill: parent
                    source: isVideo && isFullscreen ? modelData : ""
                    fillMode: VideoOutput.PreserveAspectCrop
                    autoPlay: true
                    loops: MediaPlayer.Infinite
                    muted: !audioUnlocked
                    volume: audioUnlocked ? 1.0 : 0.0
                    onSourceChanged: {
                      if (videoPaused) pause()
                      seekTimer.restart()
                    }
                  }

                  Timer {
                    id: seekTimer
                    interval: 100
                    repeat: false
                    onTriggered: {
                      if (isFullscreen) fullscreenVideo.seek(playbackPosition)
                      else video.seek(playbackPosition)
                    }
                  }

                  Rectangle {
                    visible: opacity > 0
                    opacity: fullscreenWindow.controlsVisible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    width: 36
                    height: 36
                    radius: 18
                    color: "#99000000"
                    Text {
                      anchors.centerIn: parent
                      text: "×"
                      color: "white"
                      font.pixelSize: 18
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: setFullscreen(false)
                    }
                  }

                  Rectangle {
                    visible: opacity > 0
                    opacity: fullscreenWindow.controlsVisible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    width: 36
                    height: 36
                    radius: 18
                    color: "#99000000"
                    Text {
                      anchors.centerIn: parent
                      text: "⤡"
                      color: "white"
                      font.pixelSize: 15
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: setFullscreen(false)
                    }
                  }

                  Rectangle {
                    visible: opacity > 0
                    opacity: fullscreenWindow.controlsVisible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 12
                    width: 36
                    height: 36
                    radius: 18
                    color: "#99000000"
                    Text {
                      anchors.centerIn: parent
                      text: videoPaused ? "▶" : "⏸"
                      color: "white"
                      font.pixelSize: 14
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        videoPaused = !videoPaused
                        if (videoPaused) fullscreenVideo.pause()
                        else fullscreenVideo.play()
                      }
                    }
                  }

                  Rectangle {
                    visible: opacity > 0
                    opacity: fullscreenWindow.controlsVisible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 12
                    width: fullscreenToggleLabel.implicitWidth + 24
                    height: 36
                    radius: 18
                    color: audioUnlocked ? "#cc2d7d46" : "#99000000"
                    border.width: 1
                    border.color: audioUnlocked ? "#4dff8a" : "#40ffffff"

                    Text {
                      id: fullscreenToggleLabel
                      anchors.centerIn: parent
                      text: audioUnlocked ? "🔊 Unmuted" : "🔇 Tap to unmute"
                      color: "#f5f5f7"
                      font.pixelSize: 13
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: audioUnlocked = !audioUnlocked
                    }
                  }

                  SeekBar {
                    visible: opacity > 0
                    opacity: (fullscreenWindow.controlsVisible || hovered || dragging) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 60
                    position: fullscreenVideo.position
                    duration: fullscreenVideo.duration
                    onSeekRequested: function(ms) { fullscreenVideo.seek(ms) }
                  }
                }

                MouseArea {
                  id: videoArea
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                  id: fullscreenToggle
                  visible: opacity > 0
                  opacity: isVideo && videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.margins: 7
                  width: 30
                  height: 30
                  radius: 15
                  color: "#99000000"
                  Text { anchors.centerIn: parent; text: "⤢"; color: "white"; font.pixelSize: 15 }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: setFullscreen(true)
                  }
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  visible: opacity > 0
                  opacity: videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.margins: 7
                  width: 30
                  height: 30
                  radius: 15
                  color: "#99000000"
                  Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 18 }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeMedia(index)
                  }
                }

                Rectangle {
                  id: pauseToggle
                  visible: opacity > 0
                  opacity: isVideo && videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.leftMargin: 7
                  anchors.bottomMargin: 18
                  width: 30
                  height: 30
                  radius: 15
                  color: "#99000000"
                  Text {
                    anchors.centerIn: parent
                    text: videoPaused ? "▶" : "⏸"
                    color: "white"
                    font.pixelSize: 12
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      videoPaused = !videoPaused
                      if (isFullscreen) {
                        if (videoPaused) fullscreenVideo.pause()
                        else fullscreenVideo.play()
                      } else {
                        if (videoPaused) video.pause()
                        else video.play()
                      }
                    }
                  }
                }

                Rectangle {
                  id: audioToggle
                  visible: opacity > 0
                  opacity: isVideo && videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.top: parent.top
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.topMargin: 7
                  width: toggleLabel.implicitWidth + 20
                  height: 24
                  radius: 12
                  color: audioUnlocked ? "#cc2d7d46" : "#99000000"
                  border.width: 1
                  border.color: audioUnlocked ? "#4dff8a" : "#40ffffff"

                  Text {
                    id: toggleLabel
                    anchors.centerIn: parent
                    text: audioUnlocked ? "🔊 Unmuted" : "🔇 Tap to unmute"
                    color: "#f5f5f7"
                    font.pixelSize: 11
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: audioUnlocked = !audioUnlocked
                  }
                }
              }
            }
          }
        }
      }

      DropArea {
        id: dropArea
        anchors.fill: parent
        anchors.margins: 2
        onEntered: dropHighlight.visible = true
        onExited: dropHighlight.visible = false
        onDropped: function(drop) {
          dropHighlight.visible = false
          for (var i = 0; i < drop.urls.length; ++i)
            root.addMedia(drop.urls[i].toString())
          drop.acceptProposedAction()
        }

        Rectangle {
          id: dropHighlight
          anchors.fill: parent
          radius: 16
          color: "transparent"
          border.width: 2
          border.color: "#66ffffff"
          visible: false
        }
      }
    }
  }
}
