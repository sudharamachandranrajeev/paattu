import QtQuick
import QtQuick.Effects
import "Model.js" as Model

// Now Playing: the cover big and glowing, the song, and what's up next, in
// one of four looks (Settings › Now Playing): the cover (in 3D when that's
// on), the cover making way for the song's video, the picture across the
// window (AppWindow draws it), or the cover on a turning record. AppWindow
// shows the song's video behind it all, blurred (VideoBackdrop). The cover in
// 3D moves with the song: its rhythm (`paattu rhythm`, paattu/rhythm.py) is
// followed as it plays. Video mode (the Audio | Video switch) shows the song's
// video in a wide card in the cover's place, the engine playing its sound.
Item {
  id: root

  required property var app
  readonly property var pal: app.playerPal
  readonly property string style: app.nowPlayingStyle
  readonly property bool depth: app.store.config.coverDepth !== false
  readonly property var player: app.player
  readonly property var track: app.nowTrack
  readonly property var upNext: Model.queueRows(player.playlist, app.store.tracks)
    .filter(function(row) { return row.index > player.index }).slice(0, 6)
  readonly property bool videoOn: app.store.config.videoBackground !== false
  readonly property bool videoMode: app.store.config.videoMode === true
  readonly property real artSize: Math.max(160, Math.min(420, height - 64, (width - 84) * 0.45))
  // The song as the library has it (year, language, views...), when it does.
  readonly property var known: (track.id && app.store.tracks[track.id]) || ({})
  readonly property var words: coverWords.words
  readonly property bool hasWords: !!(words && words.found)
  readonly property bool showWords: app.lyricsOpen && hasWords

  // The song's rhythm ({fps, level, punch} for `rhythmFor`, the engine's
  // path) and where it is: loudness followed smoothly, the beat jumping up
  // and dying away. The engine's position comes once a second, so it is
  // carried on between.
  property var rhythm: null
  property string rhythmFor: ""
  property real beatLevel: 0
  property real beatPunch: 0
  property real positionAt: Date.now()
  property int beatFrame: -1
  readonly property bool beating: rhythm !== null && rhythmFor === player.path && player.playing
    && depth && style !== "record" && style !== "full" && !videoMode && visible
  onBeatingChanged: if (!beating) { beatLevel = 0; beatPunch = 0; beatFrame = -1 }

  Connections {
    target: root.player
    function onPositionChanged() { root.positionAt = Date.now() }
    function onPathChanged() { rhythmSoon.restart() }
  }
  Component.onCompleted: rhythmSoon.restart()
  onDepthChanged: rhythmSoon.restart()

  // Skipping through songs doesn't work every one out.
  Timer {
    id: rhythmSoon
    interval: 1500
    onTriggered: root.findRhythm()
  }

  Jobs { id: rhythmJobs }

  function findRhythm() {
    var asked = player.path
    if (!asked || !depth || rhythmFor === asked) return
    if (rhythmJobs.busy) {
      rhythmSoon.restart()
      return
    }
    rhythmJobs.run(["rhythm", "--", asked], "", function(ok, e) {
      if (ok && e.level && e.level.length) {
        root.rhythm = e
        root.rhythmFor = asked
      } else if (!ok) {
        console.warn("paattu: rhythm: " + (e && e.message || "failed"))
      }
    })
  }

  FrameAnimation {
    running: root.beating
    onTriggered: {
      var r = root.rhythm
      var at = root.player.position + (Date.now() - root.positionAt) / 1000
      var frame = Math.max(0, Math.min(r.level.length - 1, Math.floor(at * r.fps)))
      // Every frame since the last refresh counts; a seek starts afresh.
      var from = root.beatFrame < 0 || frame < root.beatFrame || frame - root.beatFrame > 10 ? frame : root.beatFrame + 1
      root.beatFrame = frame
      var hit = 0
      for (var i = from; i <= frame; i++) hit = Math.max(hit, r.punch[i] / 255)
      var loud = r.level[frame] / 255
      var step = Math.min(0.1, frameTime)
      root.beatLevel += (loud - root.beatLevel) * (1 - Math.exp(-step * (loud > root.beatLevel ? 30 : 8)))
      root.beatPunch = Math.max(hit, root.beatPunch * Math.exp(-step * 9))
    }
  }

  // The cover, with the accent glowing under it.
  Item {
    id: art
    x: 28
    anchors.verticalCenter: parent.verticalCenter
    visible: root.videoMode || root.style !== "full"
    width: !visible ? 0 : root.videoMode ? Math.min(root.artSize * 16 / 9, (root.width - 84) * 0.58) : root.artSize
    height: root.videoMode ? width * 9 / 16 : root.artSize
    // The video takes the cover's place once it shows.
    opacity: !root.videoMode && root.style === "video" && root.app.videoShown ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 18
      anchors.topMargin: 36
      radius: root.style === "record" && !root.videoMode ? width / 2 : 40
      color: root.pal.accent
      opacity: 0.55
      visible: GraphicsInfo.api !== GraphicsInfo.Software
      layer.enabled: visible
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 64
        blur: 1
        autoPaddingEnabled: true
      }
    }
    Cover {
      anchors.fill: parent
      visible: root.videoMode || (root.style !== "record" && !root.depth)
      radius: 32
      source: visible && root.track.id ? root.app.store.artFor("v", root.track.id) : ""
      revision: root.app.artRevision
      tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
      glyphColor: root.pal.muted
      glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      fontFamily: root.app.fontFamily
    }
    Loader {
      anchors.fill: parent
      active: !root.videoMode && root.style !== "record" && root.style !== "full" && root.depth
      sourceComponent: DepthCover {
        app: root.app
        beatLevel: root.beatLevel
        beatPunch: root.beatPunch
        trackId: root.track.id || ""
        radius: 32
        tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
        glyphColor: root.pal.muted
        glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      }
    }
    Record {
      anchors.fill: parent
      visible: !root.videoMode && root.style === "record"
      source: visible && root.track.id ? root.app.store.artFor("v", root.track.id) : ""
      revision: root.app.artRevision
      spinning: visible && root.player.playing
      turn: 6000
      labelTint: root.pal.accent
      glyphColor: root.pal.accentText
      holeColor: root.pal.background
      fontFamily: root.app.fontFamily
    }
    // Video mode: the video, sharp, over the cover once it plays.
    Item {
      anchors.fill: parent
      visible: root.videoMode && root.app.videoTexture !== null
      opacity: root.app.videoShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 600 } }
      layer.enabled: visible
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: videoMask
      }
      Rectangle { anchors.fill: parent; color: "black" }
      ShaderEffect {
        // The picture is 16 by 9; fitted into the card it fills it.
        anchors.fill: parent
        property var source: root.app.videoTexture
      }
    }
    Rectangle {
      id: videoMask
      anchors.fill: parent
      radius: 32
      visible: false
      layer.enabled: true
    }
  }

  // The words over the top of the cover (or of the window, when the picture fills it).
  CoverLyrics {
    id: coverWords
    app: root.app
    track: root.track
    x: root.style === "full" ? (root.width - width) / 2 : art.x
    y: root.style === "full" ? 8 : art.y
    width: root.style === "full" ? Math.min(560, root.width - 56) : root.artSize
    height: root.style === "full" ? 200 : root.artSize
    // Not over the video: the Lyrics chip shows them beside it.
    visible: !root.videoMode
    z: 1
  }

  Column {
    id: info
    anchors.left: art.right
    anchors.leftMargin: root.style === "full" ? 8 : 36
    anchors.right: parent.right
    anchors.rightMargin: 28
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10

    Row {
      spacing: 14
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "NOW PLAYING"
        color: root.pal.accent
        font.family: root.app.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 2
      }
      // Audio | Video: video mode shows the song's video and plays its sound.
      Row {
        spacing: 4
        Chip {
          text: "Audio"
          glyph: Model.GLYPH_NOTE
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: !root.videoMode
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: if (root.videoMode) root.app.setVideoMode(false)
        }
        Chip {
          text: "Video"
          glyph: Model.GLYPH_VIDEO
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: root.videoMode
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: if (!root.videoMode) root.app.setVideoMode(true)
        }
      }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.player.hasTrack ? (root.track.title || "…") : "Nothing playing"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 34
      font.weight: Font.Black
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      text: root.player.hasTrack ? [Model.subtitle(root.track)].concat((root.track.credits || []).slice(1, 3))
        .filter(function(s) { return s }).join(" · ") : "Pick a song, a playlist or a mix to start."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 15
      elide: Text.ElideRight
    }

    Row {
      spacing: 8
      topPadding: 4
      visible: root.player.hasTrack

      // The stream: "AAC · 320 kbps".
      Glass {
        pal: root.pal
        visible: root.player.quality !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: qualityText.implicitWidth + 24
        height: 30
        radius: 15
        Text {
          id: qualityText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.player.quality
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 11
        }
      }
      SongActions {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.player.videoId !== ""
        store: root.app.store
        jobs: root.app.quick
        videoId: root.player.videoId
        showSave: true
        color: root.pal.foreground
        accent: root.pal.accent
        size: 34
        fontFamily: root.app.fontFamily
        onPick: function(anchor) { root.app.pickPlaylists(root.track, anchor) }
      }
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: "Blurred video"
        glyph: Model.GLYPH_VIDEO
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.videoOn
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.setConfig("videoBackground", !root.videoOn)
      }
      // All the words, in place of Up next.
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasWords
        text: "Lyrics"
        glyph: Model.GLYPH_NOTE
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.showWords
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.lyricsOpen = !root.app.lyricsOpen
      }
      // Songs like this one, without end (on by itself when a queue runs
      // out, unless auto radio is off in Settings).
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: root.player.radioOn ? "Radio on" : "Start radio"
        glyph: Model.GLYPH_RADIO
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.player.radioOn
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.toggleRadio()
      }
      // Sleep timer: each press goes 15, 30, 60 min, end of this song, off.
      // (The position ticks while playing, so the minutes left stay fresh.)
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.sleepLabel(root.player.sleep, root.player.position >= 0 ? Date.now() / 1000 : 0)
        glyph: Model.GLYPH_SLEEP
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: !!root.player.sleep.mode
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.player.setSleep(Model.nextSleep(root.player.sleep, Date.now() / 1000))
      }
    }

    Item { width: 1; height: 10 }

    // What the song is: the film and year, singers and music, language, label, site, plays.
    Glass {
      pal: root.pal
      visible: root.player.hasTrack && root.app.store.config.songInfo !== false && infoText.text !== ""
      width: Math.min(parent.width, 560)
      height: 38
      radius: 19
      Text {
        id: infoText
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        width: parent.width - 32
        textFormat: Text.PlainText
        text: Model.songFacts(root.track, root.known)
          .join("   ·   ")
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
    }

    // All the words, the line being sung lit up and kept in sight.
    Glass {
      pal: root.pal
      visible: root.showWords
      width: Math.min(parent.width, 560)
      height: Math.min(360, Math.max(160, root.height - y - 40))
      radius: 28
      ListView {
        id: wordsList
        anchors.fill: parent
        anchors.margins: 14
        clip: true
        model: root.showWords ? root.words.lines : []
        currentIndex: coverWords.line
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height * 0.3
        preferredHighlightEnd: height * 0.5
        highlightMoveDuration: 500
        header: Text {
          width: wordsList.width
          bottomPadding: 8
          textFormat: Text.PlainText
          text: [root.words ? root.words.language : "", root.words ? root.words.source : "",
                 root.words && !root.words.synced ? "not timed" : ""].filter(function(s) { return s }).join(" · ")
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 11
        }
        delegate: Column {
          required property var modelData
          required property int index
          width: wordsList.width
          bottomPadding: modelData.text ? 8 : 4
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.text
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: index === coverWords.line ? root.pal.accent : root.pal.foreground
            opacity: index === coverWords.line || coverWords.line < 0 ? 1 : 0.7
            font.family: root.app.fontFamily
            font.pixelSize: 15
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.latin || ""
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: root.pal.muted
            font.family: root.app.fontFamily
            font.pixelSize: 12
          }
        }
      }
    }

    // Up next
    Glass {
      pal: root.pal
      visible: root.upNext.length > 0 && !root.showWords
      width: Math.min(parent.width, 560)
      height: nextColumn.implicitHeight + 20
      radius: 28

      Column {
        id: nextColumn
        x: 10
        y: 10
        width: parent.width - 20
        Text {
          leftPadding: 12
          topPadding: 4
          bottomPadding: 6
          textFormat: Text.PlainText
          text: "Up next"
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
          font.bold: true
        }
        Repeater {
          model: root.upNext
          TrackRow {
            required property var modelData
            width: nextColumn.width
            app: root.app
            compact: true
            track: root.app.store.tracks[modelData.id] || { id: modelData.id, title: modelData.title, movie: modelData.movie }
            number: modelData.index + 1
            onActivated: root.player.playIndex(modelData.index)
          }
        }
      }
    }
  }
}
