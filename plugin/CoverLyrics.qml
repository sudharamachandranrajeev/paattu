import QtQuick
import QtQuick.Effects
import "Model.js" as Model

// The song's words over the top of the cover on Now Playing (`paattu
// lyrics`, paattu/lyrics.py): the line being sung, its English letters under
// it, coming in as Settings › Lyrics says (popping out of the cover in 3D,
// fading, or plain) and filled with the cover's own colours moving slowly
// through the letters. The engine's position comes once a second, so it is
// carried on between. The words are kept in `words` for the Lyrics panel.
Item {
  id: root

  required property var app
  required property var track
  readonly property var player: app.player
  readonly property var settings: app.store.config.lyrics || ({})
  readonly property bool on: settings.show !== false
  readonly property string effect: settings.effect || "3d"
  readonly property bool moving: settings.gradient !== false
  // The gradient needs the GPU; on the software renderer the words are one colour.
  readonly property bool fancy: GraphicsInfo.api !== GraphicsInfo.Software

  // What `paattu lyrics` found ({found, synced, lines: [{time, text, latin}]}), for wordsFor.
  property var words: null
  property string wordsFor: ""
  property int line: -1
  property real positionAt: Date.now()
  readonly property bool timed: !!(words && words.found && words.synced)

  Connections {
    target: root.player
    function onPositionChanged() { root.positionAt = Date.now() }
  }
  onTrackChanged: lookSoon.restart()
  onOnChanged: lookSoon.restart()
  Component.onCompleted: lookSoon.restart()
  property bool latin: settings.transliterate !== false
  onLatinChanged: { wordsFor = ""; lookSoon.restart() }

  // Skipping through songs doesn't look every one up.
  Timer {
    id: lookSoon
    interval: 600
    onTriggered: root.look()
  }

  Jobs { id: jobs }

  function look() {
    var id = root.track.id || ""
    if (id === wordsFor || !on) return
    if (jobs.busy) {
      lookSoon.restart()
      return
    }
    wordsFor = id
    words = null
    line = -1
    if (!id) return
    var args = ["lyrics"]
    if (!root.track.known) {
      if (root.track.title) args.push("--title=" + root.track.title)
      if (root.track.movie) args.push("--movie=" + root.track.movie)
      if (root.player.duration > 0) args.push("--duration=" + Math.round(root.player.duration))
    }
    jobs.run(args.concat(["--", id]), "", function(ok, e) {
      if (root.wordsFor !== id) return
      if (ok) root.words = e
      else console.warn("paattu: lyrics: " + (e && e.message || "failed"))
    })
  }

  // The line being sung, a little early so it's in place as it's sung.
  Timer {
    interval: 100
    repeat: true
    running: root.timed && root.on && root.visible
    onTriggered: {
      var at = root.player.position + (root.player.playing ? (Date.now() - root.positionAt) / 1000 : 0) + 0.25
      var lines = root.words.lines
      var found = -1
      for (var i = 0; i < lines.length && lines[i].time <= at; i++) found = i
      if (found !== root.line) root.line = found
    }
  }

  // Taken from the cover whatever the theme: bright colours that read on the shade.
  CoverPalette {
    id: colours
    base: ({ background: "#101010", surface: "#202020", foreground: "#ffffff", muted: "#bbbbbb",
             accent: root.app.pal.accent, highlight: root.app.pal.highlight || root.app.pal.accent })
    source: root.on && root.track.id ? root.app.store.artFor("v", root.track.id) : ""
  }
  readonly property var tints: [colours.palette.accent, colours.palette.highlight, Qt.lighter(colours.palette.accent, 1.5)]

  // The gradient's place, sliding along once every nine seconds.
  property real flow: 0
  NumberAnimation on flow {
    from: 0; to: 1
    duration: 9000
    loops: Animation.Infinite
    running: root.moving && root.fancy && root.timed && root.visible
  }

  readonly property var shown: line >= 0 && timed ? words.lines[line] : null
  readonly property bool speaking: !!(shown && shown.text)

  // A shade across the top of the cover, so the words read on any picture.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height * 0.62
    radius: 32
    opacity: root.speaking && root.on ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600 } }
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.6) }
      GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.32) }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
    }
  }

  // Two lines take turns: the one being sung and the one going.
  property int front: 0
  onShownChanged: {
    if (!on) return
    var coming = front === 0 ? second : first
    var going = front === 0 ? first : second
    coming.place(shown ? shown.text : "", shown ? shown.latin || "" : "")
    going.leave()
    front = 1 - front
  }

  component Line: Item {
    id: lineItem
    property string text: ""
    property string latin: ""
    // 0 away, 1 in place; coming in from below, going up and over.
    property real t: 0
    property bool coming: true
    property bool instant: false

    function place(words, letters) {
      instant = true
      coming = true
      t = 0
      text = words
      latin = letters
      instant = false
      t = 1
    }
    function leave() {
      coming = false
      t = 0
    }

    Behavior on t {
      enabled: !lineItem.instant && root.effect !== "plain"
      NumberAnimation {
        // The line going is out of the way quickly, so the two don't sit on each other.
        duration: !lineItem.coming ? 380 : root.effect === "3d" ? 640 : 450
        easing.type: lineItem.coming ? (root.effect === "3d" ? Easing.OutBack : Easing.OutCubic) : Easing.OutQuad
        easing.overshoot: 1.2
      }
    }

    x: 18
    y: 20 + (root.effect === "plain" ? 0 : (coming ? 30 : -24) * (1 - t))
    width: root.width - 36
    height: column.implicitHeight
    opacity: Math.max(0, Math.min(1, t))
    visible: opacity > 0.01 && text !== ""
    transform: [
      Rotation {
        origin.x: lineItem.width / 2
        origin.y: lineItem.height / 2
        axis { x: 1; y: 0; z: 0 }
        angle: root.effect === "3d" ? (lineItem.coming ? -55 : 42) * (1 - lineItem.t) : 0
      },
      Scale {
        origin.x: lineItem.width / 2
        origin.y: lineItem.height / 2
        xScale: root.effect === "3d" ? 0.78 + 0.22 * lineItem.t : 1
        yScale: xScale
      }
    ]

    Column {
      id: column
      width: parent.width
      spacing: 4
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: lineItem.text
        color: root.fancy && root.moving ? "white" : root.tints[0]
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.45)
        font.family: root.app.fontFamily
        font.pixelSize: Math.max(16, Math.min(28, root.width / 14))
        font.weight: Font.ExtraBold
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: lineItem.latin
        color: root.fancy && root.moving ? Qt.rgba(1, 1, 1, 0.86) : Qt.rgba(1, 1, 1, 0.9)
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.45)
        font.family: root.app.fontFamily
        font.pixelSize: Math.max(12, Math.min(18, root.width / 22))
        font.weight: Font.DemiBold
        font.letterSpacing: 0.3
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }

  Item {
    id: lines
    anchors.fill: parent
    visible: root.on && root.timed
    Line { id: first }
    Line { id: second }
  }

  // The cover's colours, three times over so the slide loops without a seam;
  // the words, as a mask, let them through.
  Item {
    id: tintSource
    anchors.fill: parent
    visible: false
    clip: true
    layer.enabled: root.fancy
    Rectangle {
      width: root.width * 2
      height: parent.height
      x: -root.width * root.flow
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0 / 6; color: root.tints[0] }
        GradientStop { position: 1 / 6; color: root.tints[1] }
        GradientStop { position: 2 / 6; color: root.tints[2] }
        GradientStop { position: 3 / 6; color: root.tints[0] }
        GradientStop { position: 4 / 6; color: root.tints[1] }
        GradientStop { position: 5 / 6; color: root.tints[2] }
        GradientStop { position: 6 / 6; color: root.tints[0] }
      }
    }
  }
  ShaderEffectSource {
    id: wordsMask
    anchors.fill: parent
    sourceItem: lines
    hideSource: root.fancy && root.moving
    visible: false
    live: true
  }
  MultiEffect {
    anchors.fill: parent
    visible: root.fancy && root.moving && root.on && root.timed
    source: tintSource
    maskEnabled: true
    maskSource: wordsMask
    // The words' shade (their drop shadow) shows as dark, not coloured.
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.3
  }

  // Words that aren't timed: a button for the panel.
  Chip {
    anchors.top: parent.top
    anchors.topMargin: 14
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.on && !!(root.words && root.words.found) && !root.timed
    text: "Lyrics"
    glyph: Model.GLYPH_NOTE
    textColor: root.app.playerPal.foreground
    accent: root.app.playerPal.accent
    fontSize: 12
    fontFamily: root.app.fontFamily
    onClicked: root.app.lyricsOpen = !root.app.lyricsOpen
  }
}
