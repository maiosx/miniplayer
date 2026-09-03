import QtQuick

// Minimal translucent seek/progress bar. Bind `position`/`duration` (both in
// milliseconds) and handle `seekRequested(ms)` to perform the actual seek.
Item {
  id: seekBar

  property real position: 0
  property real duration: 0
  property bool hovered: mouseArea.containsMouse
  property bool dragging: mouseArea.pressed
  property real fraction: duration > 0 ? Math.min(1, Math.max(0, position / duration)) : 0
  property real dragFraction: fraction
  property real displayFraction: dragging ? dragFraction : fraction

  signal seekRequested(real ms)

  height: hovered || dragging ? 10 : 6

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: seekBar.hovered || seekBar.dragging ? 4 : 3
    radius: height / 2
    color: "#40ffffff"
    Behavior on height { NumberAnimation { duration: 120 } }
  }

  Rectangle {
    anchors.left: track.left
    anchors.verticalCenter: track.verticalCenter
    height: track.height
    radius: height / 2
    width: track.width * seekBar.displayFraction
    color: "#f5f5f7"
  }

  Rectangle {
    visible: (seekBar.hovered || seekBar.dragging) && seekBar.duration > 0
    width: 10
    height: 10
    radius: 5
    color: "#f5f5f7"
    anchors.verticalCenter: track.verticalCenter
    x: Math.min(track.width - width / 2, Math.max(-width / 2, track.width * seekBar.displayFraction - width / 2))
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    anchors.topMargin: -8
    anchors.bottomMargin: -8
    hoverEnabled: true
    enabled: seekBar.duration > 0
    cursorShape: Qt.PointingHandCursor
    preventStealing: true

    function fractionAt(mx) {
      return Math.min(1, Math.max(0, mx / width))
    }

    onPressed: function(mouse) {
      seekBar.dragFraction = fractionAt(mouse.x)
    }
    onPositionChanged: function(mouse) {
      if (pressed) seekBar.dragFraction = fractionAt(mouse.x)
    }
    onReleased: function(mouse) {
      var f = fractionAt(mouse.x)
      seekBar.dragFraction = f
      seekBar.seekRequested(f * seekBar.duration)
    }
  }
}
