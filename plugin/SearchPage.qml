import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Search: new songs online (JioSaavn, YouTube, SoundCloud, or the song behind
// a pasted link), then what's already in your library (songs by title, movie
// or composer; playlists; users). Typing searches the library; Enter or the
// button searches online.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property string query: app.query.trim()
  readonly property bool isLink: Model.isLink(query)
  readonly property var results: isLink ? { tracks: [], playlists: [], users: [] } : Model.search(app.store.lib, app.query, 60)
  readonly property bool inLibrary: results.tracks.length + results.playlists.length + results.users.length > 0
  readonly property var online: app.online
  // The online results are for what's in the box now (or the box is empty).
  readonly property bool fresh: online.query !== "" && (online.query === query || query === "")
  readonly property var groups: fresh ? Model.searchGroups(online.results, app.onlineSite) : []
  readonly property var allGroups: fresh ? Model.searchGroups(online.results, "") : []
  readonly property var errors: fresh ? Object.keys(online.errors || {}).map(function(site) {
    return Model.siteName(site) + ": " + online.errors[site]
  }) : []

  readonly property var notes: ({
    jiosaavn: "Film albums from the labels · up to 320 kbps AAC",
    youtube: "Everything else · Opus, about 130–160 kbps",
    soundcloud: "Covers, remixes and independent artists",
    link: ""
  })

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Column {
    id: column
    x: 28
    y: 8
    width: root.width - 56
    spacing: 22

    // ---------- online ----------
    Column {
      width: parent.width
      spacing: 10

      Row {
        spacing: 14
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.isLink ? "From a link" : "Search online"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 22
          font.bold: true
        }
        // Filter the results by site.
        Repeater {
          model: root.allGroups.length > 1 ? [{ site: "", title: "All" }].concat(root.allGroups) : []
          Chip {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.title + (modelData.tracks ? "  " + modelData.tracks.length : "")
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: root.app.onlineSite === modelData.site
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: root.app.onlineSite = modelData.site
          }
        }
      }

      Text {
        width: parent.width
        visible: !root.query && !root.fresh && !root.online.busy
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Type a song, a film or a singer in the box above and press Enter to search JioSaavn, YouTube "
          + "and SoundCloud. Or paste a link to a song or an album on any site (JioSaavn, YouTube, SoundCloud, "
          + "Bandcamp, Audiomack, archive.org, an mp3 or flac file…). Play it, heart it, save it to your "
          + "library or add it to a playlist."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 13
        lineHeight: 1.25
      }

      // Search for what's typed (when it hasn't been searched yet).
      Chip {
        visible: root.query !== "" && root.online.query !== root.query
        text: root.isLink ? "Find the songs at this link" : "Search JioSaavn, YouTube and SoundCloud for “" + root.query + "”"
        glyph: root.isLink ? Model.GLYPH_LINK : Model.GLYPH_SEARCH
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: true
        fontSize: 13
        fontFamily: root.app.fontFamily
        onClicked: root.app.searchOnline(root.query)
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.online.busy && root.fresh
          ? (Model.isLink(root.online.query) ? "Looking up the link…"
             : "Searching JioSaavn, YouTube and SoundCloud for “" + root.online.query + "”…")
          : !root.fresh ? ""
          : root.online.error ? root.online.error
          : root.online.results.length === 0 ? "Nothing found for “" + root.online.query + "”"
          : Model.plural(root.online.results.length, "song") + " for “" + root.online.query + "”"
            + (root.errors.length ? "  ·  " + root.errors.join("  ·  ") : "")
        color: root.fresh && !root.online.busy && (root.online.error || root.errors.length) ? root.pal.accent : root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }

      Repeater {
        model: root.groups

        Column {
          id: group
          required property var modelData
          width: column.width
          spacing: 2
          topPadding: 8

          Row {
            spacing: 10
            bottomPadding: 6
            Text {
              id: groupTitle
              textFormat: Text.PlainText
              text: group.modelData.title
              color: root.pal.foreground
              font.family: root.app.fontFamily
              font.pixelSize: 16
              font.bold: true
            }
            Text {
              anchors.baseline: groupTitle.baseline
              textFormat: Text.PlainText
              text: root.notes[group.modelData.site] || ""
              color: root.pal.muted
              font.family: root.app.fontFamily
              font.pixelSize: 11
            }
          }
          Repeater {
            model: group.modelData.tracks
            TrackRow {
              required property var modelData
              required property int index
              width: column.width
              app: root.app
              track: modelData
              number: index + 1
              found: true
              current: root.app.player.videoId === modelData.id
              playing: current && root.app.player.playing
              onActivated: root.app.playSong(modelData)
              onPlayNext: root.app.queueSong(modelData, true)
            }
          }
        }
      }
    }

    // ---------- your library ----------
    Rectangle {
      width: parent.width
      height: 1
      visible: root.query !== "" && !root.isLink
      color: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
    }

    Column {
      width: parent.width
      spacing: 22
      visible: root.query !== "" && !root.isLink

      Text {
        textFormat: Text.PlainText
        text: "In your library"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 22
        font.bold: true
      }

      Text {
        visible: !root.inLibrary
        textFormat: Text.PlainText
        text: "Nothing in your library matches “" + root.app.query + "”."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 13
      }

      Column {
        width: parent.width
        spacing: 4
        visible: root.results.tracks.length > 0
        Text {
          textFormat: Text.PlainText
          text: "Songs"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 16
          font.bold: true
          bottomPadding: 6
        }
        Repeater {
          model: root.results.tracks
          TrackRow {
            required property var modelData
            required property int index
            width: column.width
            app: root.app
            track: modelData.track
            number: index + 1
            current: root.app.player.videoId === modelData.track.id
            playing: current && root.app.player.playing
            onActivated: root.app.playPlaylist(modelData.playlist, false, modelData.track.id)
          }
        }
      }

      Column {
        width: parent.width
        spacing: 14
        visible: root.results.playlists.length > 0
        Text {
          textFormat: Text.PlainText
          text: "Playlists"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 16
          font.bold: true
        }
        Flow {
          width: parent.width
          spacing: 24
          Repeater {
            model: root.results.playlists.slice(0, 15)
            PlaylistCard {
              required property var modelData
              app: root.app
              playlist: modelData
              size: 150
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: 6
        visible: root.results.users.length > 0
        Text {
          textFormat: Text.PlainText
          text: "YouTube users"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 16
          font.bold: true
        }
        Flow {
          width: parent.width
          spacing: 8
          Repeater {
            model: root.results.users
            Chip {
              required property var modelData
              text: modelData.name
              glyph: Model.GLYPH_USER
              textColor: root.pal.foreground
              accent: root.pal.accent
              fontSize: 12
              fontFamily: root.app.fontFamily
              onClicked: root.app.openUser(modelData.id)
            }
          }
        }
      }
    }
  }
}
