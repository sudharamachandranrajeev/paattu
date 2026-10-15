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
  property var themes: []

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Component.onCompleted: themeProc.running = true

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
    Hint { app: root.app; width: column.width; text: "Behind Now Playing: a bit of the song's video, blurred, silent and kept in time with the music (about 1 MB a minute). Songs from JioSaavn or SoundCloud use a YouTube video of the same length when there is one." }

    Row {
      spacing: 8
      Text {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Video"
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
