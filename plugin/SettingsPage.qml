import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Look & settings — Spicetify-style: colour schemes are plain files in
// ~/.config/paattu/themes, everything here is also `paattu config set ...`,
// and changes apply live without restarting anything.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property var desktop: app.store.desktop
  readonly property var lyrics: app.store.config.lyrics || ({})
  property var themes: []

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Component.onCompleted: {
    themeProc.running = true
    lbStatus.running = true
  }

  Process {
    id: themeProc
    command: ["paattu", "--json", "theme", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.themes = JSON.parse(text).themes } catch (e) { root.themes = [] }
      }
    }
  }

  function set(key, value) { root.app.setConfig(key, value) }

  // ListenBrainz: who plays are scrobbled as ("" when not connected), and
  // what the last connect or sync said.
  property string lbUser: ""
  property string lbMessage: ""

  Process {
    id: lbStatus
    command: ["paattu", "--json", "listenbrainz", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.lbUser = JSON.parse(text).user || "" } catch (e) { root.lbUser = "" }
      }
    }
  }

  // The token goes in the environment, so it stays out of the process list.
  Process {
    id: lbLogin
    property string token: ""
    command: ["paattu", "--json", "listenbrainz", "login"]
    environment: ({ PAATTU_LISTENBRAINZ_TOKEN: token })
    stdout: SplitParser {
      onRead: function(line) {
        var e = Model.parseEvent(line)
        if (e && (e.event === "done" || e.event === "error" || e.event === "progress")) root.lbMessage = e.message || ""
      }
    }
    onExited: {
      token = ""
      lbStatus.running = true
    }
  }

  function connectListenBrainz(token) {
    token = (token || "").trim()
    if (!token || lbLogin.running) return
    lbMessage = "Checking the token…"
    lbLogin.token = token
    lbLogin.running = true
  }

  // Inline components can't see this file's ids, so they take `app`.
  component Stepper: Row {
    id: stepper
    required property var app
    property string label: ""
    property string valueText: ""
    signal down()
    signal up()
    spacing: 6
    Text {
      width: 110
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: stepper.label
      color: stepper.app.pal.muted
      font.family: stepper.app.fontFamily
      font.pixelSize: 12
    }
    GlyphButton { glyph: "\u{F0374}"; size: 28; color: stepper.app.pal.foreground; fontFamily: stepper.app.fontFamily; onClicked: stepper.down() }
    Text {
      width: 52
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: stepper.valueText
      color: stepper.app.pal.foreground
      font.family: stepper.app.fontFamily
      font.pixelSize: 13
      font.bold: true
    }
    GlyphButton { glyph: Model.GLYPH_ADD; size: 28; color: stepper.app.pal.foreground; fontFamily: stepper.app.fontFamily; onClicked: stepper.up() }
  }

  Column {
    id: column
    x: 28
    y: 8
    width: Math.min(820, root.width - 56)
    spacing: 16

    Text {
      textFormat: Text.PlainText
      text: "Look & settings"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 28
      font.weight: Font.Black
    }

    // ---------- Colour scheme ----------
    SectionTitle { app: root.app; text: "Colour scheme" }
    Hint { app: root.app; width: column.width; text: "Omarchy follows whatever theme you switch to. The others are files in ~/.config/paattu/themes — copy one, change the colours, and it shows up here." }

    Flow {
      width: parent.width
      spacing: 14
      Repeater {
        model: root.themes
        Rectangle {
          id: swatch
          required property var modelData
          readonly property bool current: root.app.store.themeName === modelData.name
          readonly property var colors: modelData.name === "omarchy" ? root.app.store.rawPalette : modelData
          width: 172
          height: 104
          radius: 22
          color: colors.background || "#000000"
          border.width: current ? 2 : 1
          border.color: current ? root.pal.accent : Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.15)

          Row {
            x: 12
            y: 12
            spacing: 6
            Repeater {
              model: ["accent", "highlight", "foreground", "muted"]
              Rectangle {
                required property string modelData
                width: 18
                height: 18
                radius: 9
                color: swatch.colors[modelData] || "#888888"
              }
            }
          }
          Column {
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: parent.width - 24
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: swatch.modelData.title + (swatch.current ? "  " + Model.GLYPH_CHECK : "")
              color: swatch.colors.foreground || "#ffffff"
              font.family: root.app.fontFamily
              font.pixelSize: 13
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: swatch.modelData.description || ""
              color: swatch.colors.muted || "#aaaaaa"
              font.family: root.app.fontFamily
              font.pixelSize: 10
              elide: Text.ElideRight
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.set("theme", swatch.modelData.name)
          }
        }
      }
    }

    // ---------- Music from ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Music from" }
    Hint { app: root.app; width: column.width; text: "Where search looks: YouTube has nearly everything, JioSaavn the film albums at 320 kbps, SoundCloud covers and remixes. Albums come from JioSaavn and SoundCloud whichever you pick." }

    Flow {
      width: column.width
      spacing: 8
      readonly property var sites: (root.app.store.config.search || {}).sites || ["youtube"]
      readonly property string chosen: sites.length === 1 ? sites[0] : "all"
      Repeater {
        model: [{ id: "youtube", title: "YouTube" }, { id: "jiosaavn", title: "JioSaavn" },
          { id: "soundcloud", title: "SoundCloud" }, { id: "all", title: "Every site" }]
        Chip {
          required property var modelData
          text: modelData.title
          textColor: root.pal.foreground; accent: root.pal.accent
          selected: parent.chosen === modelData.id
          fontSize: 12; fontFamily: root.app.fontFamily
          onClicked: root.set("search.sites", modelData.id === "all"
            ? ["jiosaavn", "youtube", "soundcloud"] : [modelData.id])
        }
      }
    }

    // ---------- Now Playing ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Now Playing" }
    Hint { app: root.app; width: column.width; text: "How Now Playing looks. Behind it: the song's video, blurred as much as you like, silent and kept in time with the music (about 1 MB a minute). Songs from JioSaavn or SoundCloud use a YouTube video of the same length when there is one." }

    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Look"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Repeater {
        model: [{ v: "cover", l: "Cover" }, { v: "video", l: "Video first" }, { v: "full", l: "Full picture" },
          { v: "record", l: "Record" }]
        Chip {
          required property var modelData
          text: modelData.l
          textColor: root.pal.foreground; accent: root.pal.accent
          selected: root.app.nowPlayingStyle === modelData.v
          fontSize: 12; fontFamily: root.app.fontFamily
          onClicked: root.set("nowPlayingStyle", modelData.v)
        }
      }
    }
    Hint {
      app: root.app
      width: column.width
      text: ({ cover: "The cover, with the song's video behind it.",
        video: "The cover makes way for the song's video when there is one.",
        full: "The picture fills the window, sharp, with the video over it.",
        record: "The cover on a record that turns while the song plays." })[root.app.nowPlayingStyle] || ""
    }

    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Video mode"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.videoMode === true
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.app.setVideoMode(!on)
      }
    }
    Hint {
      app: root.app
      width: column.width
      text: "Shows the song's video and plays its own sound, so the singing matches the lips (up to 720p, about 10 MB a minute). Also Audio | Video on Now Playing."
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Blurred video"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.videoBackground !== false
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("videoBackground", !on)
      }
    }
    Stepper {
      app: root.app
      readonly property int blur: root.app.store.config.videoBlur === undefined ? 30 : root.app.store.config.videoBlur
      label: "Video blur"
      valueText: blur ? String(blur) : "None"
      onDown: root.set("videoBlur", Math.max(0, Math.ceil(blur / 10) * 10 - 10))
      onUp: root.set("videoBlur", Math.min(100, Math.floor(blur / 10) * 10 + 10))
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Cover in 3D"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.coverDepth !== false
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("coverDepth", !on)
      }
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Cover colours"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.coverColors === true
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("coverColors", !on)
      }
    }
    Hint { app: root.app; width: column.width; text: "Cover in 3D gives the cover depth, the people in it (or its layers) gliding as it tilts with the pointer (it runs U²-Net through uv, on this computer; the first time, uv fetches ONNX Runtime). Cover colours gives Now Playing and the player bar the colours of the song's cover." }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "About the song"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.songInfo !== false
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("songInfo", !on)
      }
    }

    // ---------- Lyrics ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Lyrics" }
    Hint { app: root.app; width: column.width; text: "The line being sung, over the top of the cover on Now Playing, from LRCLIB (in the song's own script, timed) or YouTube Music. A line in Malayalam, Tamil, Hindi, Telugu or Kannada has how it sounds in English letters under it. The Lyrics button shows all the words in place of Up next." }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Over the cover"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.lyrics.show !== false
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("lyrics.show", !on)
      }
    }
    Row {
      spacing: 8
      Text {
        width: 110
        textFormat: Text.PlainText
        text: "Each line"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
        topPadding: 6
      }
      // Six choices: they wrap rather than run off the page.
      Flow {
        width: column.width - 118
        spacing: 8
        Repeater {
          model: [{ key: "3d", label: "Pops out in 3D" }, { key: "comic", label: "Comic pop" },
                  { key: "karaoke", label: "Karaoke" }, { key: "glow", label: "Glows in" },
                  { key: "fade", label: "Fades in" }, { key: "plain", label: "Plain" }]
          Chip {
            required property var modelData
            text: modelData.label
            textColor: root.pal.foreground; accent: root.pal.accent
            selected: (root.lyrics.effect || "3d") === modelData.key
            fontSize: 12; fontFamily: root.app.fontFamily
            onClicked: root.set("lyrics.effect", modelData.key)
          }
        }
      }
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Cover's colours"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.lyrics.gradient !== false
        text: on ? "Moving through the words" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("lyrics.gradient", !on)
      }
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "English letters"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.lyrics.transliterate !== false
        text: on ? "Under the words" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("lyrics.transliterate", !on)
      }
    }

    // ---------- Playback ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Between songs" }
    Hint { app: root.app; width: column.width; text: "A song fades out over its last seconds and the next one fades in (0 s: no fade). Auto radio carries on with songs like the last one when the queue runs out, unless repeat is on or you turned the radio off." }

    Stepper {
      app: root.app
      readonly property int fade: root.app.store.config.fade === undefined ? 3 : root.app.store.config.fade
      label: "Fade"
      valueText: fade ? fade + " s" : "Off"
      onDown: root.set("fade", Math.max(0, fade - 1))
      onUp: root.set("fade", Math.min(12, fade + 1))
    }
    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Auto radio"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        readonly property bool on: root.app.store.config.autoRadio !== false
        text: on ? "On" : "Off"
        glyph: on ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: on
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("autoRadio", !on)
      }
    }

    // ---------- Desktop widget ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Desktop widget" }
    Hint { app: root.app; width: column.width; text: "Lives on your home workspace, behind your windows. Right-click it to flip through styles, scroll on it for volume." }

    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Show"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Chip {
        text: root.desktop.enabled !== false ? "On" : "Off"
        glyph: root.desktop.enabled !== false ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: root.desktop.enabled !== false
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.set("desktop.enabled", root.desktop.enabled === false)
      }
    }

    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Style"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Repeater {
        model: [{ v: "vinyl", l: "Vinyl" }, { v: "card", l: "Card" }, { v: "minimal", l: "Minimal" }]
        Chip {
          required property var modelData
          text: modelData.l
          textColor: root.pal.foreground; accent: root.pal.accent
          selected: root.desktop.style === modelData.v
          fontSize: 12; fontFamily: root.app.fontFamily
          onClicked: root.set("desktop.style", modelData.v)
        }
      }
    }

    Row {
      spacing: 8
      Text {
        width: 110
        textFormat: Text.PlainText
        text: "Position"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Grid {
        columns: 3
        spacing: 4
        Repeater {
          model: Model.POSITIONS
          Rectangle {
            required property string modelData
            readonly property bool current: root.desktop.position === modelData
            width: 46
            height: 30
            radius: 6
            color: current ? Qt.rgba(root.pal.accent.r, root.pal.accent.g, root.pal.accent.b, 0.3)
              : Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, posMouse.containsMouse ? 0.12 : 0.06)
            border.width: current ? 1 : 0
            border.color: root.pal.accent
            Rectangle {
              readonly property var a: Model.anchorsFor(parent.modelData)
              width: 12
              height: 7
              radius: 2
              color: parent.current ? root.pal.accent : root.pal.muted
              x: a.left ? 5 : a.right ? parent.width - width - 5 : (parent.width - width) / 2
              y: a.top ? 5 : a.bottom ? parent.height - height - 5 : (parent.height - height) / 2
            }
            MouseArea {
              id: posMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.set("desktop.position", parent.modelData)
            }
          }
        }
      }
    }

    Stepper {
      app: root.app
      label: "Workspace"
      valueText: String(root.desktop.workspace || 1)
      onDown: root.set("desktop.workspace", Math.max(1, (root.desktop.workspace || 1) - 1))
      onUp: root.set("desktop.workspace", Math.min(10, (root.desktop.workspace || 1) + 1))
    }
    Stepper {
      app: root.app
      label: "Size"
      valueText: Math.round((root.desktop.scale || 1) * 100) + "%"
      onDown: root.set("desktop.scale", Math.max(0.6, Math.round(((root.desktop.scale || 1) - 0.1) * 10) / 10))
      onUp: root.set("desktop.scale", Math.min(2, Math.round(((root.desktop.scale || 1) + 0.1) * 10) / 10))
    }
    Stepper {
      app: root.app
      label: "Opacity"
      valueText: Math.round((root.desktop.opacity === undefined ? 0.92 : root.desktop.opacity) * 100) + "%"
      onDown: root.set("desktop.opacity", Math.max(0, Math.round(((root.desktop.opacity === undefined ? 0.92 : root.desktop.opacity) - 0.1) * 100) / 100))
      onUp: root.set("desktop.opacity", Math.min(1, Math.round(((root.desktop.opacity === undefined ? 0.92 : root.desktop.opacity) + 0.1) * 100) / 100))
    }

    // ---------- ListenBrainz ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "Sync between devices" }
    Hint {
      app: root.app
      width: column.width
      text: root.lbUser
        ? "Scrobbling to ListenBrainz as " + root.lbUser + ". Songs you play here and in the Paattu app show up in each one's history, made-for-you playlists and mixes."
        : "Scrobble to ListenBrainz and songs you play here and in the Paattu app show up in each one's history, made-for-you playlists and mixes. "
          + "Paste your user token from listenbrainz.org/settings. Your listening history on ListenBrainz is public."
    }
    Row {
      visible: !root.lbUser
      spacing: 8
      InputBox {
        id: lbToken
        width: Math.min(360, column.width - 120)
        app: root.app
        glyph: Model.GLYPH_LINK
        placeholder: "ListenBrainz user token"
        echoMode: TextInput.Password
        onAccepted: { root.connectListenBrainz(text); text = "" }
      }
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: "Connect"
        glyph: Model.GLYPH_CHECK
        enabled: !lbLogin.running
        textColor: root.pal.foreground; accent: root.pal.accent
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: { root.connectListenBrainz(lbToken.text); lbToken.text = "" }
      }
    }
    Row {
      visible: root.lbUser !== ""
      spacing: 8
      Chip {
        text: "Sync now"
        glyph: Model.GLYPH_REFRESH
        textColor: root.pal.foreground; accent: root.pal.accent
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.app.jobs.run(["listenbrainz", "sync"], "Syncing with ListenBrainz…", function(ok, event) {
          root.lbMessage = event && event.message ? event.message : ""
        })
      }
      Chip {
        text: "Stop scrobbling"
        glyph: Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.app.jobs.run(["listenbrainz", "logout"], "", function() {
          root.lbMessage = ""
          lbStatus.running = true
        })
      }
    }
    Hint {
      app: root.app
      width: column.width
      visible: root.lbMessage !== ""
      text: root.lbMessage
      color: root.pal.accent
    }

    // ---------- cliamp ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "cliamp" }
    Hint { app: root.app; width: column.width; text: "Copy your saved playlists into cliamp (Super+Shift+Alt+M) so the terminal player has the same Malayalam & Tamil library, with its EQ and visualizer." }
    Chip {
      text: "Export library to cliamp"
      glyph: Model.GLYPH_OPEN
      textColor: root.pal.foreground; accent: root.pal.accent
      fontSize: 12; fontFamily: root.app.fontFamily
      onClicked: root.app.jobs.run(["export", "cliamp"], "Writing cliamp playlists…")
    }
    Hint {
      app: root.app
      width: column.width
      visible: root.app.jobs.lastDone !== "" && root.app.jobs.lastDone.indexOf("cliamp") !== -1
      text: root.app.jobs.lastDone
      color: root.pal.accent
    }

    // ---------- About ----------
    Item { width: 1; height: 8 }
    SectionTitle { app: root.app; text: "How it plays" }
    Hint {
      app: root.app
      width: column.width
      text: "Audio streams straight from YouTube through yt-dlp into a headless mpv (paattu-engine.service), so there is no "
        + "YouTube page and no ads. Media keys and the Omarchy OSD work through MPRIS. The video button opens Brave, "
        + "where Shields blocks the ads. Everything is also on the command line: paattu --help"
    }
  }
}
