import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "Model.js" as Model

// The song's words over the top of the cover on Now Playing (`paattu
// lyrics`, paattu/lyrics.py): the line being sung, its English letters under
// it, coming in as Settings › Lyrics says (popping out of the cover in 3D,
// bursting in comic-book style, filling as it's sung, glowing into focus,
// fading, or plain) and filled with the cover's own colours moving slowly
// through the letters: the colours Now Playing takes from the cover, which
// also light the glows and the bursts as lines go. The engine's position comes once a second, so it is
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
      // Karaoke: the line fills from when it starts to when the next does
      // (ten seconds at most, for a line before a long break).
      if (found >= 0 && root.effect === "karaoke") {
        var start = lines[found].time
        var next = found + 1 < lines.length ? lines[found + 1].time : start + 4
        var end = Math.min(next, start + 10)
        root.sung = end > start ? Math.max(0, Math.min(1, (at - 0.25 - start) / (end - start))) : 1
      }
    }
  }
  // How much of the line being sung has been, for Karaoke.
  property real sung: 0

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

  // A line's words and their English letters, in one colour. Laid out by
  // hand: a Column leaves out what isn't shown, and the mask isn't.
  component Words: Item {
    id: wordsItem
    property string text: ""
    property string latin: ""
    property color colour: "white"
    property bool raised: true
    readonly property real wide: Math.max(main.contentWidth, latin !== "" ? letters.contentWidth : 0)
    implicitHeight: main.height + (latin !== "" ? 4 + letters.height : 0)
    Text {
      id: main
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: wordsItem.text
      color: wordsItem.colour
      style: wordsItem.raised ? Text.Raised : Text.Normal
      styleColor: Qt.rgba(0, 0, 0, 0.45)
      font.family: root.app.fontFamily
      font.pixelSize: Math.max(16, Math.min(28, root.width / 14))
      font.weight: Font.ExtraBold
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }
    Text {
      id: letters
      y: main.height + 4
      width: parent.width
      visible: text !== ""
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: wordsItem.latin
      color: Qt.rgba(wordsItem.colour.r, wordsItem.colour.g, wordsItem.colour.b, wordsItem.colour.a * 0.88)
      style: wordsItem.raised ? Text.Raised : Text.Normal
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

  // The cover's colours, three times over so the slide loops without a seam.
  component Tint: Item {
    clip: true
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

  // One line, coming in or going as the effect has it. 3D: out of the cover
  // towards you, tipping up from below into focus with a glow of the song's
  // colours, and away up and over in a burst of them. Comic pop: springing
  // in a little askew on a starburst, white letters outlined dark, popping
  // away bigger in a burst. Karaoke: filling with the colours as it's sung.
  // Glow: out of a blur, glowing, then rising away into one.
  component Line: Item {
    id: lineItem
    property string text: ""
    property string latin: ""
    // 0 away, 1 in place; coming in from below, going up and over.
    property real t: 0
    property bool coming: true
    property bool instant: false
    // The burst of colours as it goes, 0 to 1.
    property real burst: 1
    readonly property real away: 1 - Math.max(0, Math.min(1, t))
    readonly property string effect: root.effect
    readonly property bool comic: effect === "comic"
    readonly property bool filled: root.fancy && root.moving && !comic
    readonly property real sung: !coming ? 1 : effect === "karaoke" ? root.sung : 1

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
      if (text !== "" && root.fancy && (effect === "3d" || comic)) bursting.restart()
    }

    Behavior on t {
      enabled: !lineItem.instant && root.effect !== "plain"
      NumberAnimation {
        // The line going is out of the way quickly, so the two don't sit on each other.
        duration: !lineItem.coming ? 380 : lineItem.effect === "3d" ? 640 : lineItem.comic ? 760
                                         : lineItem.effect === "glow" ? 720 : 450
        easing.type: !lineItem.coming ? Easing.OutQuad : lineItem.comic ? Easing.OutElastic
                     : lineItem.effect === "3d" ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: 1.2
        easing.amplitude: 1.0
        easing.period: 0.45
      }
    }
    NumberAnimation {
      id: bursting
      target: lineItem
      property: "burst"
      from: 0; to: 1
      duration: 750
      easing.type: Easing.OutCubic
    }

    x: 18
    y: 20
    width: root.width - 36
    height: plain.implicitHeight

    Item {
      id: body
      width: parent.width
      height: parent.height
      y: lineItem.effect === "plain" ? 0
         : lineItem.effect === "glow" ? (lineItem.coming ? 6 : -22) * lineItem.away
         : lineItem.comic ? 0 : (lineItem.coming ? 30 : -24) * lineItem.away
      opacity: Math.max(0, Math.min(1, lineItem.t))
      visible: opacity > 0.01 && lineItem.text !== ""
      // Coming into focus out of a blur (3D, Glow), or going into one.
      readonly property real blur: !root.fancy ? 0
          : lineItem.effect === "3d" ? lineItem.away * 0.5
          : lineItem.effect === "glow" ? lineItem.away * 0.75
          : lineItem.comic ? (lineItem.coming ? 0 : lineItem.away * 0.2)
          : lineItem.effect === "plain" ? 0 : lineItem.away * 0.3
      layer.enabled: blur > 0.01
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: body.blur
        blurMax: 24
        autoPaddingEnabled: true
      }
      transform: [
        Rotation {
          origin.x: body.width / 2
          origin.y: body.height / 2
          axis { x: 1; y: 0; z: 0 }
          angle: lineItem.effect === "3d" ? (lineItem.coming ? -55 : 42) * lineItem.away : 0
        },
        Rotation {
          origin.x: body.width / 2
          origin.y: body.height / 2
          angle: lineItem.comic ? -3 + (lineItem.coming ? -7 * lineItem.away : 3.5 * lineItem.away) : 0
        },
        Scale {
          origin.x: body.width / 2
          origin.y: body.height / 2
          xScale: lineItem.effect === "3d" ? 0.78 + 0.22 * lineItem.t
                  : lineItem.comic ? (lineItem.coming ? 0.35 + 0.65 * lineItem.t : 1 + 0.3 * lineItem.away)
                  : lineItem.effect === "glow" ? (lineItem.coming ? 0.96 + 0.04 * lineItem.t : 1 + 0.04 * lineItem.away)
                  : 1
          yScale: xScale
        }
      ]

      // Comic pop: a starburst of the song's colours behind the words.
      Shape {
        id: star
        visible: lineItem.comic
        readonly property real rx: plain.wide / 2 + 30
        readonly property real ry: plain.implicitHeight / 2 + 22
        readonly property real cx: body.width / 2
        readonly property real cy: body.height / 2
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        function points(dx, dy) {
          var out = []
          for (var i = 0; i <= 36; i++) {
            var spike = i % 2 === 0 ? 1 + 0.12 * Math.sin(i * 2.7) : 0.8
            var a = i * Math.PI / 18
            out.push(Qt.point(cx + dx + Math.cos(a) * rx * spike, cy + dy + Math.sin(a) * ry * spike))
          }
          return out
        }
        ShapePath {
          strokeWidth: -1
          fillColor: Qt.rgba(0.08, 0.06, 0.1, 0.5)
          PathPolyline { path: star.visible ? star.points(3, 4) : [] }
        }
        ShapePath {
          strokeColor: "#14101a"
          strokeWidth: 3
          joinStyle: ShapePath.RoundJoin
          fillGradient: LinearGradient {
            readonly property real slide: Math.sin(root.flow * 2 * Math.PI) * star.rx * 0.8
            x1: star.cx - star.rx + slide; y1: star.cy - star.ry
            x2: star.cx + star.rx + slide; y2: star.cy + star.ry
            spread: ShapeGradient.ReflectSpread
            GradientStop { position: 0; color: root.tints[0] }
            GradientStop { position: 0.5; color: root.tints[1] }
            GradientStop { position: 1; color: root.tints[2] }
          }
          PathPolyline { path: star.visible ? star.points(0, 0) : [] }
        }
      }
      // Comic pop: the letters' thick dark outline, the words drawn round them.
      Repeater {
        model: lineItem.comic ? [[-3, 0], [3, 0], [0, -3], [0, 3], [-2, -2], [2, -2], [-2, 2], [2, 2], [3, 4]] : []
        Words {
          required property var modelData
          x: modelData[0]
          y: modelData[1]
          width: body.width
          text: lineItem.text
          latin: lineItem.latin
          colour: "#14101a"
          raised: false
        }
      }

      // A glow of the song's colour behind the letters: on the way in for
      // 3D, all along (brighter as it comes and goes) for Glow.
      Words {
        readonly property real amount: lineItem.effect === "glow" ? 0.85 + 0.15 * lineItem.away
            : lineItem.effect === "3d" && lineItem.coming ? Math.sin(Math.max(0, Math.min(1, lineItem.t)) * Math.PI) * 0.9
            : 0
        visible: root.fancy && amount > 0.02
        opacity: amount
        width: body.width
        text: lineItem.text
        latin: lineItem.latin
        raised: false
        layer.enabled: visible
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1
          blurMax: 20
          colorization: 1
          colorizationColor: root.tints[0]
          brightness: 0.35
        }
      }

      // The letters, plain (white for Comic pop, or one colour without the
      // GPU), or Karaoke's dim part not yet sung.
      Words {
        id: plain
        width: body.width
        text: lineItem.text
        latin: lineItem.latin
        opacity: !lineItem.filled || lineItem.sung < 1 ? 1 : 0
        colour: lineItem.comic ? "white" : lineItem.filled ? Qt.rgba(1, 1, 1, 0.45) : root.tints[0]
        raised: !lineItem.comic
      }
      // The letters as a mask: the cover's colours show through them.
      Words {
        id: mask
        width: body.width
        // As big as the colours it masks, so the two line up.
        height: body.height
        text: lineItem.text
        latin: lineItem.latin
        raised: false
        visible: root.fancy
      }
      ShaderEffectSource {
        id: maskSource
        width: body.width
        height: body.height
        sourceItem: root.fancy ? mask : null
        hideSource: true
        visible: false
      }
      Item {
        // Karaoke: as much as has been sung.
        width: body.width * lineItem.sung
        height: body.height
        clip: true
        visible: lineItem.filled
        Tint {
          id: tint
          width: body.width
          height: body.height
          visible: false
          layer.enabled: lineItem.filled
        }
        // Shaded like the plain letters, so they read on any picture.
        Words {
          y: 1.5
          width: body.width
          text: lineItem.text
          latin: lineItem.latin
          colour: Qt.rgba(0, 0, 0, 0.45)
          raised: false
        }
        MultiEffect {
          width: body.width
          height: body.height
          source: tint
          // No padding: the mask lines up with the letters only unpadded.
          autoPaddingEnabled: false
          maskEnabled: true
          maskSource: maskSource
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.3
        }
      }
    }

    // Bits of the song's colours flying out from a line as it goes in 3D or
    // comic-book style: dots, or stars and dashes. The same scatter each time.
    Repeater {
      model: 16
      Item {
        required property int index
        readonly property real angle: index * 2 * Math.PI / 16 + Math.sin(index * 12.9898) * 0.35
        readonly property real far: Math.max(lineItem.width, lineItem.height) * 0.55
                                    * (0.55 + 0.45 * (Math.sin(index * 78.233) + 1) / 2) * lineItem.burst
        readonly property color colour: root.tints[index % root.tints.length]
        visible: lineItem.burst > 0 && lineItem.burst < 1
        x: lineItem.width / 2 + Math.cos(angle) * far
        y: lineItem.height / 2 + Math.sin(angle) * far * 0.6
        opacity: (1 - lineItem.burst) * Math.min(1, lineItem.burst * 6)
        Rectangle {
          visible: !lineItem.comic
          readonly property real r: 3.2 * (1 - 0.5 * lineItem.burst)
          x: -r; y: -r
          width: r * 2; height: r * 2; radius: r
          color: parent.colour
        }
        Text {
          visible: lineItem.comic && index % 2 === 0
          anchors.centerIn: parent
          text: "★"
          color: parent.colour
          font.pixelSize: 16 * (1 - 0.5 * lineItem.burst)
          rotation: parent.angle * 57.3
        }
        Rectangle {
          visible: lineItem.comic && index % 2 === 1
          width: 12 * (1 - 0.5 * lineItem.burst); height: 3; radius: 1.5
          x: -width; y: -1.5
          color: parent.colour
          rotation: parent.angle * 57.3
          transformOrigin: Item.Right
        }
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
