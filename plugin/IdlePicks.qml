import QtQuick
import "Model.js" as Model

// Shown when nothing is playing: a greeting in Malayalam or Tamil and one-tap
// starts for each mix, plus a way into the app.
Column {
  id: root

  required property var store
  property var pal: store.palette
  property real s: 1
  property string fontFamily: "monospace"
  property bool compact: false
  property date now: new Date()
  readonly property var greet: Model.greeting(now, store.languages)

  signal playMix(string mixId, string title)
  signal openApp()

  spacing: 10 * s

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.greet.native
    color: root.pal.foreground
    font.family: root.greet.language === "Tamil" ? "Noto Serif Tamil" : "Noto Serif Malayalam"
    font.pixelSize: (root.compact ? 22 : 28) * root.s
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.store.hasLibrary
      ? root.greet.english + " — what are we listening to?"
      : "Your library is empty. Open Paattu and add a YouTube profile or playlist."
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: 12 * root.s
    wrapMode: Text.WordWrap
  }

  Flow {
    width: parent.width
    spacing: 8 * root.s

    Repeater {
      model: root.store.hasLibrary ? root.store.mixes : []

      Chip {
        required property var modelData
        text: modelData.title
        glyph: Model.GLYPH_SHUFFLE
        textColor: root.pal.foreground
        accent: root.pal.accent
        fontSize: 12 * root.s
        fontFamily: root.fontFamily
        onClicked: root.playMix(modelData.id, modelData.title)
      }
    }

    Chip {
      text: "Open Paattu"
      glyph: Model.GLYPH_LIBRARY
      textColor: root.pal.foreground
      accent: root.pal.accent
      fontSize: 12 * root.s
      fontFamily: root.fontFamily
      onClicked: root.openApp()
    }
  }

  Timer {
    interval: 60000
    running: root.visible
    repeat: true
    onTriggered: root.now = new Date()
  }
}
