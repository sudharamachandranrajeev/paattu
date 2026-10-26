import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Model.js" as Model

// Your music in numbers (`paattu stats`): how much you listened, the titles
// your listening earned, what you played most and at what hour, over a week,
// a month, three months or all of it.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property var periods: [{ days: 7, label: "Week" }, { days: 30, label: "Month" },
    { days: 90, label: "3 months" }, { days: 0, label: "All time" }]
  property int days: 30
  property var stats: null
  readonly property int peak: stats ? Math.max.apply(null, stats.hours.concat([1])) : 1

  clip: true
  contentHeight: body.height + 40
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  function load() {
    statsProc.command = ["paattu", "--json", "stats"].concat(days ? ["--days", String(days)] : [])
    statsProc.running = true
  }
  onDaysChanged: load()
  Component.onCompleted: load()

  Process {
    id: statsProc
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var e = Model.parseEvent(lines[lines.length - 1])
        if (e && e.plays !== undefined) root.stats = e
      }
    }
  }

  Column {
    id: body
    x: 28
    y: 0
    width: root.width - 56
    spacing: 12

    Text {
      textFormat: Text.PlainText
      text: "Your music in numbers"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 28
      font.weight: Font.Black
    }
    Flow {
      width: parent.width
      spacing: 8
      Repeater {
        model: root.periods
        Chip {
          required property var modelData
          text: modelData.label
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: root.days === modelData.days
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.days = modelData.days
        }
      }
    }
    Text {
      visible: !!root.stats && root.stats.plays === 0
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Nothing played in this time. Play a few songs to the end and the numbers fill in."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 13
    }

    Flow {
      visible: !!root.stats && root.stats.plays > 0
      width: parent.width
      spacing: 10
      Repeater {
        model: root.stats ? [
          [String(root.stats.plays), "plays"],
          [root.stats.minutes >= 120 ? (root.stats.minutes / 60).toFixed(1) + " h" : root.stats.minutes + " min", "listened"],
          [String(root.stats.songs), "songs"],
          [String(root.stats.artists), "singers & composers"],
          [String(root.stats.skips), "skips"],
          [String(root.stats.streak), "days in a row"]
        ] : []
        Glass {
          required property var modelData
          pal: root.pal
          width: 150
          height: 76
          radius: 18
          Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 2
            Text {
              textFormat: Text.PlainText
              text: modelData[0]
              color: root.pal.foreground
              font.family: root.app.fontFamily
              font.pixelSize: 22
              font.weight: Font.Black
            }
            Text {
              textFormat: Text.PlainText
              text: modelData[1]
              color: root.pal.muted
              font.family: root.app.fontFamily
              font.pixelSize: 12
            }
          }
        }
      }
    }

    SectionTitle {
      app: root.app
      visible: titles.count > 0
      topPadding: 8
      text: "Titles you earned"
    }
    Repeater {
      id: titles
      model: root.stats ? root.stats.quirks : []
      Column {
        required property var modelData
        width: body.width
        Text {
          textFormat: Text.PlainText
          text: modelData[0]
          color: root.pal.accent
          font.family: root.app.fontFamily
          font.pixelSize: 15
          font.bold: true
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: modelData[1]
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
        }
      }
    }

    Repeater {
      model: root.stats ? [["Most played", root.stats.top_songs], ["Singers and composers", root.stats.top_artists],
        ["Films", root.stats.top_films]] : []
      Column {
        required property var modelData
        visible: modelData[1].length > 0
        width: body.width
        spacing: 4
        SectionTitle {
          app: root.app
          topPadding: 8
          bottomPadding: 4
          text: modelData[0]
        }
        Repeater {
          model: modelData[1]
          Text {
            required property var modelData
            required property int index
            width: body.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: (index + 1) + ".  " + modelData[0] + "  ·  " + Model.plural(modelData[1], "play")
            color: root.pal.foreground
            font.family: root.app.fontFamily
            font.pixelSize: 13
          }
        }
      }
    }

    SectionTitle {
      app: root.app
      visible: !!root.stats && root.stats.plays > 0
      topPadding: 8
      text: "When you listen"
    }
    Row {
      visible: !!root.stats && root.stats.plays > 0
      height: 80
      spacing: 3
      Repeater {
        model: 24
        Rectangle {
          required property int index
          readonly property int plays: root.stats ? root.stats.hours[index] : 0
          anchors.bottom: parent.bottom
          width: Math.max(6, (body.width - 23 * 3) / 24)
          height: Math.max(3, 72 * plays / root.peak)
          radius: 3
          color: Qt.rgba(root.pal.accent.r, root.pal.accent.g, root.pal.accent.b, plays ? 0.35 + 0.65 * plays / root.peak : 0.15)
          ToolTip.visible: hourMouse.containsMouse
          ToolTip.text: (index % 12 || 12) + (index < 12 ? " AM: " : " PM: ") + Model.plural(plays, "play")
          MouseArea { id: hourMouse; anchors.fill: parent; hoverEnabled: true }
        }
      }
    }
  }
}
