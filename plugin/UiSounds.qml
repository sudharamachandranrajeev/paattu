import QtQuick
import QtMultimedia

// Soft interface sounds, made by tools/ui-sounds.py, like the phone app's: a
// drop for a click, a breath for another page and a small singing bowl for
// another song, quiet enough to sit under the music. A heavier one just begun
// is never cut short by a lighter one (a click that opens a page gets the
// breath alone). Off with uiSounds in the config.
Item {
  id: root

  property bool on: true
  readonly property var weights: ({ tap: 0, move: 1, change: 2 })
  property string playing: ""
  property double since: 0

  function play(name) {
    if (!on) return
    var now = Date.now()
    if (playing && weights[playing] > weights[name] && now - since < 200) return
    playing = name
    since = now
    var sound = name === "change" ? change : name === "move" ? move : tap
    sound.play()
  }

  SoundEffect { id: tap; source: Qt.resolvedUrl("ui-tap.wav") }
  SoundEffect { id: move; source: Qt.resolvedUrl("ui-move.wav") }
  SoundEffect { id: change; source: Qt.resolvedUrl("ui-change.wav") }
}
