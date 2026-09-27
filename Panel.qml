import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Touchpad scroll speed bar widget. Click the icon, drag the slider; the new
// speed applies live through `hyprctl eval` and is saved to
// ~/.local/share/omarchy-scroll-speed/speed. The saved speed is re-applied
// when the shell starts and whenever Hyprland reloads its config, so it
// survives reboots and config edits. Colors and fonts come from the shell's
// theme singletons, so the widget follows `omarchy theme set`.
Panel {
  id: root
  moduleName: "spacelemonade.scroll-speed"
  ipcTarget: "spacelemonade.scroll-speed"

  readonly property string storePath: Quickshell.env("HOME") + "/.local/share/omarchy-scroll-speed/speed"
  readonly property real defaultSpeed: 0.4   // Omarchy's stock scroll_factor
  readonly property real minSpeed: 0.1
  readonly property real maxSpeed: 2.0
  property real speed: defaultSpeed
  property bool saved: false   // a speed has been chosen with this widget
  property real pendingSpeed: defaultSpeed

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function clamp(value) {
    var rounded = Math.round(value * 100) / 100
    return Math.max(minSpeed, Math.min(maxSpeed, rounded))
  }

  function format(value) {
    return value.toFixed(2) + "×"
  }

  function apply(value) {
    applyProc.running = false
    applyProc.command = ["hyprctl", "eval",
      "hl.config({ input = { touchpad = { scroll_factor = " + clamp(value).toFixed(2) + " } } })"]
    applyProc.running = true
  }

  function preview(value) {
    pendingSpeed = clamp(value)
    previewDebounce.restart()
  }

  function setSpeed(value) {
    previewDebounce.stop()
    speed = clamp(value)
    saved = true
    apply(speed)
    store.setText(speed.toFixed(2) + "\n")
  }

  function load(raw) {
    var value = parseFloat(String(raw || "").trim())
    if (isNaN(value)) {
      readProc.running = true
      return
    }
    speed = clamp(value)
    saved = true
    apply(speed)
  }

  FileView {
    id: store
    path: root.storePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: readProc.running = true
  }

  // No saved speed yet: show whatever Hyprland is currently using.
  Process {
    id: readProc
    command: ["hyprctl", "-j", "getoption", "input:touchpad:scroll_factor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = JSON.parse(text).float
          if (typeof value === "number" && !root.saved) root.speed = root.clamp(value)
        } catch (e) {}
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: previewDebounce
    interval: 60
    onTriggered: root.apply(root.pendingSpeed)
  }

  // A Hyprland config reload resets scroll_factor to the config value.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded" && root.saved) root.apply(root.speed)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰝀"
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: slider
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: title.implicitHeight

        Text {
          id: title
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: "Scroll Speed"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: title.verticalCenter
          textFormat: Text.PlainText
          text: root.format(slider.dragging ? root.clamp(slider.liveValue) : root.speed)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      PanelSlider {
        id: slider
        bar: root.bar
        width: parent.width
        minimum: root.minSpeed
        maximum: root.maxSpeed
        step: 0.05
        value: root.speed
        focus: true
        onMoved: function(v) { root.preview(v) }
        onReleased: function(v) { root.setSpeed(v) }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.setSpeed(root.speed - slider.step)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.setSpeed(root.speed + slider.step)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }
      }

      Item {
        width: parent.width
        implicitHeight: slowLabel.implicitHeight

        Text {
          id: slowLabel
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: "Slower"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "Faster"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Scroll here to feel the current speed without leaving the panel.
      Rectangle {
        width: parent.width
        height: Style.space(110)
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

        ListView {
          id: sample
          anchors.fill: parent
          anchors.margins: Style.space(8)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: 60

          delegate: Text {
            required property int index
            width: sample.width
            textFormat: Text.PlainText
            text: index === 0 ? "Scroll here to try it out" : "Line " + (index + 1)
            color: index === 0 ? root.fg : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)
          }
        }
      }

      Button {
        visible: Math.abs(root.speed - root.defaultSpeed) > 0.001
        anchors.right: parent.right
        text: "Reset to " + root.format(root.defaultSpeed)
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.setSpeed(root.defaultSpeed)
      }
    }
  }
}
