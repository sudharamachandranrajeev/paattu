import QtQuick

// A section heading on the settings-style pages.
Text {
  required property var app
  textFormat: Text.PlainText
  color: app.pal.foreground
  font.family: app.fontFamily
  font.pixelSize: 18
  font.bold: true
}
