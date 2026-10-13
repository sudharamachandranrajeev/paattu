import QtQuick
import "Model.js" as Model

// A remove button that asks once: the first click arms it, the second one
// removes. It disarms itself after a few seconds. With an empty label it is
// just the trash glyph until armed.
Chip {
  id: root

  property string label: "Remove"
  property string confirmLabel: "Click again to remove"
  property color danger: "#e06c75"
  property bool armed: false

  signal confirmed()

  text: armed ? confirmLabel : label
  glyph: Model.GLYPH_DELETE
  accent: danger
  selected: armed

  onClicked: {
    if (armed) {
      armed = false
      confirmed()
    } else {
      armed = true
      disarm.restart()
    }
  }

  Timer {
    id: disarm
    interval: 3500
    onTriggered: root.armed = false
  }
}
