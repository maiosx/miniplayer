import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "miniplayer"
  implicitWidth: glyph.implicitWidth
  implicitHeight: glyph.implicitHeight

  function toggleMiniPlayer() {
    if (!root.bar) return
    if (typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell shell toggle miniplayer")
      return
    }
    if (root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle("miniplayer", "{}")
  }

  BarIconButton {
    id: glyph
    anchors.fill: parent
    bar: root.bar
    text: "▣"
    tooltipText: "MiniPlayer"
    onPressed: root.toggleMiniPlayer()
  }
}
