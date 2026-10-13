import QtQuick

// The little "now playing" equaliser: bars that bounce while music plays and
// settle when it pauses. Decorative — it doesn't analyse the audio.
Row {
  id: root

  property bool playing: false
  property color color: "#ffffff"
  property int bars: 4
  property real barWidth: 3
  property real maxHeight: 14

  spacing: Math.max(1, Math.round(barWidth * 0.6))
  height: maxHeight

  Repeater {
    model: root.bars

    Rectangle {
      id: bar
      required property int index
      anchors.bottom: parent.bottom
      width: root.barWidth
      radius: width / 2
      color: root.color
      height: root.maxHeight * 0.3

      SequentialAnimation on height {
        running: root.playing
        loops: Animation.Infinite
        alwaysRunToEnd: false
        NumberAnimation { to: root.maxHeight * (0.55 + 0.45 * ((bar.index * 37) % 10) / 10); duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
        NumberAnimation { to: root.maxHeight * (0.2 + 0.15 * (bar.index % 3)); duration: 300 + bar.index * 50; easing.type: Easing.InOutSine }
        NumberAnimation { to: root.maxHeight * (0.7 + 0.3 * ((bar.index * 13) % 7) / 7); duration: 240 + bar.index * 60; easing.type: Easing.InOutSine }
        NumberAnimation { to: root.maxHeight * 0.35; duration: 280; easing.type: Easing.InOutSine }
      }

      Behavior on height { enabled: !root.playing; NumberAnimation { duration: 300 } }
    }
  }

  onPlayingChanged: if (!playing) for (var i = 0; i < children.length; i++) if (children[i].height !== undefined) children[i].height = maxHeight * 0.3
}
