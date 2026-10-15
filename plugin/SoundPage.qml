import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Sound: a ten-band equaliser, preamp, bass, treble, balance and speed, after
// Poweramp and AIMP; `paattu sound` underneath. Moving a control changes the
// playing song at once (af-command on the engine's filter graph); letting go
// saves it through the CLI, which also sets the graph mpv keeps for the next
// songs.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal

  // What's saved (config.json); what the controls show (an edit, until the
  // save is back in config.json); the gains the engine's graph has now.
  readonly property var saved: Model.soundNormalize(app.store.config.sound)
  property var edit: null
  readonly property var s: edit || saved
  readonly property var gains: Model.soundGains(s)
  property var sent: null
  property int saving: 0
  // Controls being held: the page doesn't scroll under them.
  property int held: 0
  // A control moved but not let go yet (or still scrolling): a save coming
  // back mustn't snap it back.
  property bool dirty: false
  readonly property var presets: Model.soundPresets(s)
  readonly property string status: {
    if (!s.on) return "Off: songs play as they are. Pick a preset or move a band to turn it on."
    var parts = [presetName(s.preset) || "Custom"]
    if (gains.pre !== s.preamp)
      parts.push("preamp " + Model.soundDb(s.preamp) + " dB plays at " + Model.soundDb(gains.pre) + " dB, leaving room for the boosts")
    if (!app.player.connected) parts.push("plays with the next song")
    return parts.join("  ·  ")
  }

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: held === 0
  ScrollBar.vertical: ScrollBar {}

  // Someone else changed it (`paattu sound` in a terminal): start from there.
  onSavedChanged: {
    if (saving === 0) sent = null
    settle()
  }
  onSChanged: curve.requestPaint()

  function presetName(id) {
    for (var i = 0; i < presets.length; i++)
      if (presets[i].id === id) return presets[i].name
    return ""
  }

  // The settings with `patch` applied.
  function copy(patch) {
    var out = JSON.parse(JSON.stringify(s))
    for (var key in patch) out[key] = patch[key]
    return Model.soundNormalize(out)
  }

  // Show `next` and play it now: only the filters that changed are sent.
  function preview(next) {
    if (next.speed !== s.speed) app.player.setProperty("speed", next.speed)
    var before = sent || (saved.on ? Model.soundGains(saved) : null)
    edit = next
    if (next.on && app.player.connected) {
      var after = Model.soundGains(next)
      var commands = Model.soundCommands(before, after)
      for (var i = 0; i < commands.length; i++) app.player.send(commands[i])
      sent = after
    }
  }

  // A control moving. `shaping`: part of the equaliser (speed isn't), so
  // moving it turns the equaliser on.
  function move(patch, shaping) {
    dirty = true
    var next = copy(patch)
    if (patch.bands) next.preset = Model.soundMatchingPreset(next)
    if (shaping && !s.on) {
      next.on = true
      save(["on"])
    }
    preview(next)
  }

  // A control let go.
  function keep(args) {
    dirty = false
    save(["set"].concat(args))
  }

  // `paattu sound ARGS`, showing `next` until it's saved.
  function save(args, next) {
    if (next) {
      dirty = false
      preview(next)
    }
    saving++
    app.quick.run(["sound"].concat(args), "", function(ok, e) {
      saving--
      if (ok && e.sound) {
        // The CLI set the graph from what's saved; a control still moving goes back on top.
        sent = e.sound.on ? e.gains : null
        if (dirty && edit) preview(edit)
        else if (saving === 0) edit = e.sound
      } else if (!ok) {
        app.showToast(e.message || "Couldn't change the sound")
        if (saving === 0 && !dirty) edit = null
      }
      settle()
      if (saving === 0) settleTimer.restart()
    })
  }

  function settle() {
    if (edit && saving === 0 && !dirty && Model.soundSame(edit, saved)) edit = null
  }

  // In case config.json never matches (changed again elsewhere meanwhile).
  Timer {
    id: settleTimer
    interval: 3000
    onTriggered: if (root.saving === 0 && !root.dirty) root.edit = null
  }

  function pick(p) { save(["preset", "--", p.id], copy({ bands: p.bands, preset: p.id, on: true })) }
  function setOn(on) { save([on ? "on" : "off"], copy({ on: on })) }

  function saveAs(name) {
    name = String(name || "").trim()
    if (!name) return
    var presets = JSON.parse(JSON.stringify(s.presets))
    presets[name] = s.bands
    save(["save", "--", name], copy({ presets: presets, preset: name }))
  }

  function remove(name) {
    var presets = JSON.parse(JSON.stringify(s.presets))
    delete presets[name]
    save(["delete", "--", name], copy({ presets: presets, preset: s.preset === name ? "" : s.preset }))
  }

  function reset() { save(["reset"], Model.soundNormalize({ on: s.on, presets: s.presets })) }

  // The shape of the sound behind the sliders, on their scale: each band's
  // column centre is its frequency, an octave a column.
  function paintCurve(ctx, w, h, column) {
    ctx.reset()
    var fg = pal.foreground, accent = pal.accent
    var mid = h / 2
    var yOf = function(db) { return Math.max(-2, Math.min(h + 2, mid - db / Model.SOUND_LIMIT * mid)) }
    ctx.lineWidth = 1
    var lines = [-12, -6, 0, 6, 12]
    for (var i = 0; i < lines.length; i++) {
      ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, lines[i] === 0 ? 0.2 : 0.07)
      ctx.beginPath()
      ctx.moveTo(0, Math.round(yOf(lines[i])) + 0.5)
      ctx.lineTo(w, Math.round(yOf(lines[i])) + 0.5)
      ctx.stroke()
    }
    var shape = Model.soundCurve(s)
    var points = []
    for (var x = 0; x <= w + 2; x += 3)
      points.push([x, yOf(Model.soundResponse(shape, 31.25 * Math.pow(2, (x - column / 2) / column)))])
    var fill = ctx.createLinearGradient(0, 0, 0, h)
    fill.addColorStop(0, Qt.rgba(accent.r, accent.g, accent.b, 0.3))
    fill.addColorStop(0.5, Qt.rgba(accent.r, accent.g, accent.b, 0.02))
    fill.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0.3))
    ctx.fillStyle = fill
    ctx.beginPath()
    ctx.moveTo(0, mid)
    for (var j = 0; j < points.length; j++) ctx.lineTo(points[j][0], points[j][1])
    ctx.lineTo(points[points.length - 1][0], mid)
    ctx.closePath()
    ctx.fill()
    ctx.strokeStyle = accent
    ctx.lineWidth = 2
    ctx.lineJoin = "round"
    ctx.beginPath()
    ctx.moveTo(points[0][0], points[0][1])
    for (var k = 1; k < points.length; k++) ctx.lineTo(points[k][0], points[k][1])
    ctx.stroke()
  }

  Column {
    id: column
    x: 28
    y: 8
    width: Math.min(820, root.width - 56)
    spacing: 16

    Row {
      spacing: 16
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Sound"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 28
        font.weight: Font.Black
      }
      // The equaliser's switch.
      Rectangle {
        id: toggle
        anchors.verticalCenter: parent.verticalCenter
        width: 46
        height: 26
        radius: 13
        color: root.s.on ? root.pal.accent : Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.16)
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
          x: root.s.on ? parent.width - width - 3 : 3
          anchors.verticalCenter: parent.verticalCenter
          width: 20
          height: 20
          radius: 10
          color: root.s.on ? root.pal.accentText : root.pal.foreground
          Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.setOn(!root.s.on)
        }
      }
    }

    Hint { app: root.app; width: column.width; text: root.status }

    // ---------- Equaliser ----------
    Glass {
      id: panel
      pal: root.pal
      width: column.width
      height: 300
      radius: 28

      readonly property real columnWidth: (width - 32) / Model.SOUND_BANDS.length
      readonly property real trackTop: bandRepeater.count ? bandRepeater.itemAt(0).trackTop : 0
      readonly property real trackHeight: bandRepeater.count ? bandRepeater.itemAt(0).trackHeight : 0

      Canvas {
        id: curve
        x: 16
        y: bands.y + panel.trackTop
        width: panel.width - 32
        height: Math.max(1, panel.trackHeight)
        opacity: root.s.on ? 1 : 0.35
        onPaint: root.paintCurve(getContext("2d"), width, height, panel.columnWidth)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Behavior on opacity { NumberAnimation { duration: 150 } }
      }

      Row {
        id: bands
        x: 16
        y: 16
        height: panel.height - 32
        Repeater {
          id: bandRepeater
          model: Model.SOUND_BANDS
          BandSlider {
            required property int index
            required property var modelData
            width: panel.columnWidth
            height: bands.height
            value: root.s.bands[index]
            valueText: Model.soundDb(value)
            label: Model.soundBandLabel(modelData)
            textColor: root.pal.foreground
            mutedColor: root.pal.muted
            accent: root.s.on ? root.pal.accent : root.pal.muted
            fontFamily: root.app.fontFamily
            onPressedChanged: root.held += pressed ? 1 : -1
            onMoved: function(v) {
              var b = root.s.bands.slice()
              b[index] = v
              root.move({ bands: b }, true)
            }
            onCommitted: function(v) { root.keep(["--band=" + (index + 1) + "=" + Model.soundFmt(v)]) }
          }
        }
      }
    }

    // ---------- Presets ----------
    SectionTitle { app: root.app; text: "Presets" }
    Flow {
      width: column.width
      spacing: 8
      Repeater {
        model: root.presets
        Row {
          id: presetItem
          required property var modelData
          spacing: 2
          Chip {
            text: presetItem.modelData.name
            textColor: root.pal.foreground; accent: root.pal.accent
            selected: root.s.on && root.s.preset === presetItem.modelData.id
            fontSize: 12; fontFamily: root.app.fontFamily
            onClicked: root.pick(presetItem.modelData)
          }
          GlyphButton {
            visible: presetItem.modelData.saved
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.GLYPH_CLOSE
            size: 22
            color: root.pal.muted
            fontFamily: root.app.fontFamily
            tooltip: "Delete " + presetItem.modelData.name
            onClicked: root.remove(presetItem.modelData.id)
          }
        }
      }
    }
    InputBox {
      width: 260
      height: 32
      app: root.app
      glyph: Model.GLYPH_ADD
      placeholder: "Save these bands as…"
      onAccepted: {
        root.saveAs(text)
        text = ""
      }
    }

    // ---------- Tone ----------
    Item { width: 1; height: 4 }
    SectionTitle { app: root.app; text: "Tone" }
    Hint { app: root.app; width: column.width; text: "Drag a knob up or down, or scroll on it. Double-click puts it back." }
    Flow {
      width: column.width
      spacing: 28
      Knob {
        label: "Preamp"
        value: root.s.preamp
        from: -Model.SOUND_LIMIT; to: Model.SOUND_LIMIT; step: 0.5
        valueText: Model.soundDb(value)
        textColor: root.pal.foreground; mutedColor: root.pal.muted; accent: root.pal.accent
        fontFamily: root.app.fontFamily
        onPressedChanged: root.held += pressed ? 1 : -1
        onMoved: function(v) { root.move({ preamp: v }, true) }
        onCommitted: function(v) { root.keep(["--preamp=" + Model.soundFmt(v)]) }
      }
      Knob {
        label: "Bass"
        value: root.s.bass
        from: -Model.SOUND_LIMIT; to: Model.SOUND_LIMIT; step: 0.5
        valueText: Model.soundDb(value)
        textColor: root.pal.foreground; mutedColor: root.pal.muted; accent: root.pal.accent
        fontFamily: root.app.fontFamily
        onPressedChanged: root.held += pressed ? 1 : -1
        onMoved: function(v) { root.move({ bass: v }, true) }
        onCommitted: function(v) { root.keep(["--bass=" + Model.soundFmt(v)]) }
      }
      Knob {
        label: "Treble"
        value: root.s.treble
        from: -Model.SOUND_LIMIT; to: Model.SOUND_LIMIT; step: 0.5
        valueText: Model.soundDb(value)
        textColor: root.pal.foreground; mutedColor: root.pal.muted; accent: root.pal.accent
        fontFamily: root.app.fontFamily
        onPressedChanged: root.held += pressed ? 1 : -1
        onMoved: function(v) { root.move({ treble: v }, true) }
        onCommitted: function(v) { root.keep(["--treble=" + Model.soundFmt(v)]) }
      }
      Knob {
        label: "Balance"
        value: root.s.balance
        from: -1; to: 1; step: 0.05
        valueText: Math.abs(value) < 0.005 ? "C" : (value < 0 ? "L " : "R ") + Math.round(Math.abs(value) * 100)
        textColor: root.pal.foreground; mutedColor: root.pal.muted; accent: root.pal.accent
        fontFamily: root.app.fontFamily
        onPressedChanged: root.held += pressed ? 1 : -1
        onMoved: function(v) { root.move({ balance: v }, true) }
        onCommitted: function(v) { root.keep(["--balance=" + Model.soundHundredth(v)]) }
      }
      Knob {
        label: "Speed"
        value: root.s.speed
        from: Model.SOUND_SPEED[0]; to: Model.SOUND_SPEED[1]; origin: 1; step: 0.05
        valueText: Model.soundHundredth(value) + "×"
        textColor: root.pal.foreground; mutedColor: root.pal.muted; accent: root.pal.accent
        fontFamily: root.app.fontFamily
        onPressedChanged: root.held += pressed ? 1 : -1
        onMoved: function(v) { root.move({ speed: v }, false) }
        onCommitted: function(v) { root.keep(["--speed=" + Model.soundHundredth(v)]) }
      }
    }
    Hint { app: root.app; width: column.width; text: "Speed keeps the pitch, and stays as it is when the equaliser is off." }

    // ---------- Options ----------
    Item { width: 1; height: 4 }
    Row {
      spacing: 8
      Chip {
        text: "Keep loud songs from clipping"
        glyph: root.s.noclip ? Model.GLYPH_CHECK : Model.GLYPH_CLOSE
        textColor: root.pal.foreground; accent: root.pal.accent
        selected: root.s.noclip
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.save(["set", "--noclip=" + (root.s.noclip ? "off" : "on")], root.copy({ noclip: !root.s.noclip }))
      }
      Chip {
        text: "Reset"
        glyph: Model.GLYPH_RESTORE
        textColor: root.pal.foreground; accent: root.pal.accent
        fontSize: 12; fontFamily: root.app.fontFamily
        onClicked: root.reset()
      }
    }
    Hint {
      app: root.app
      width: column.width
      text: "With clipping kept away, the preamp is lowered by the biggest boost, so the loudest songs stay clean. "
        + "All of this is also on the command line: paattu sound --help"
    }
  }
}
