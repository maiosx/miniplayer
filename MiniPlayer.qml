pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtMultimedia

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var mediaItems: []
  property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")) + "/omarchy/miniplayer.json"

  function toggle() { opened ? dismiss() : open("{}") }
  function open(payload) { opened = true; reader.running = true }
  function close() { opened = false }
  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "miniplayer")
  }
  function save() {
    writer.running = true
  }
  function addMedia(url) {
    if (!url || root.mediaItems.indexOf(url) >= 0) return
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

  Process {
    id: reader
    command: ["sh", "-c", "if [ -f \"$1\" ]; then cat \"$1\"; else printf '%s' '[]'; fi", "miniplayer", root.configPath]
    stdout: StdioCollector { id: readerOut }
    onRunningChanged: {
      if (!running) {
        try {
          var parsed = JSON.parse(readerOut.text || "[]")
          root.mediaItems = Array.isArray(parsed) ? parsed : []
        } catch (e) { root.mediaItems = [] }
      }
    }
  }

  Process {
    id: writer
    command: ["sh", "-c", "dir=\"$(dirname \"$1\")\" && mkdir -p \"$dir\" && tmp=\"$1.tmp.$$\" && printf '%s' \"$2\" > \"$tmp\" && mv -f \"$tmp\" \"$1\"", "miniplayer", root.configPath, JSON.stringify(root.mediaItems)]
  }

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
    implicitHeight: Math.min(700, 120 + Math.max(1, root.mediaItems.length) * 230)
    anchors.top: true
    anchors.right: true
    margins.top: 52
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
              text: "+"
              onClicked: picker.open()
              ToolTip.visible: hovered
              ToolTip.text: "Add media"
            }
            Button {
              text: "×"
              onClicked: root.dismiss()
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
              text: "No pinned media — click + to add"
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
                  source: isVideo ? modelData : ""
                  fillMode: VideoOutput.PreserveAspectCrop
                  autoPlay: true
                  loops: MediaPlayer.Infinite
                  muted: !(videoArea.containsMouse || audioUnlocked)
                  volume: (videoArea.containsMouse || audioUnlocked) ? 1.0 : 0.0
                  visible: isVideo
                }

                MouseArea {
                  id: videoArea
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  visible: opacity > 0
                  opacity: isVideo && videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.margins: 7
                  width: 30
                  height: 30
                  radius: 15
                  color: "#99000000"
                  Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 18 }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.removeMedia(index)
                  }
                }

                Rectangle {
                  id: audioToggle
                  visible: opacity > 0
                  opacity: isVideo && videoArea.containsMouse ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottomMargin: 8
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
    }
  }
}
