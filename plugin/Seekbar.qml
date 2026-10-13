import QtQuick

// Thin progress line that grows on hover; click or drag to seek.
Item {
  id: root

  property real progress: 0
  property color trackColor: "#33ffffff"
  property color fillColor: "#ffffff"
  property real thickness: 3
  property bool interactive: true
  readonly property bool active: mouse.containsMouse || mouse.pressed
  property real dragProgress: -1

  signal seek(real fraction)

  implicitHeight: 14

  readonly property real shown: dragProgress >= 0 ? dragProgress : Math.max(0, Math.min(1, progress))

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.active ? root.thickness * 1.8 : root.thickness
    radius: height / 2
    color: root.trackColor
    Behavior on height { NumberAnimation { duration: 120 } }

    Rectangle {
      width: Math.max(height, parent.width * root.shown)
      height: parent.height
      radius: height / 2
      color: root.fillColor
      visible: root.shown > 0
    }
  }

  Rectangle {
    x: Math.max(0, Math.min(root.width - width, root.width * root.shown - width / 2))
    anchors.verticalCenter: parent.verticalCenter
    width: root.thickness * 4
    height: width
    radius: width / 2
    color: root.fillColor
    visible: root.interactive && root.active
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    function fraction(x) { return Math.max(0, Math.min(1, x / Math.max(1, root.width))) }
    onPressed: function(e) { root.dragProgress = fraction(e.x) }
    onPositionChanged: function(e) { if (pressed) root.dragProgress = fraction(e.x) }
    onReleased: function(e) {
      root.seek(fraction(e.x))
      root.dragProgress = -1
    }
    onCanceled: root.dragProgress = -1
  }
}
