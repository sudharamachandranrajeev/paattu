import QtQuick

// A muted line of explanation under a section heading.
Text {
  required property var app
  textFormat: Text.PlainText
  wrapMode: Text.WordWrap
  color: app.pal.muted
  font.family: app.fontFamily
  font.pixelSize: 12
}
