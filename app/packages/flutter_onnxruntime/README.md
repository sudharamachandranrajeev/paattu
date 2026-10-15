# flutter_onnxruntime (Paattu's copy)

[flutter_onnxruntime](https://github.com/masicai/flutter_onnxruntime) 1.9.0,
MIT (see LICENSE), cut down for Paattu, which uses it on Windows and Linux
only, to find the subject of a song's cover (Android asks ML Kit instead):

- Only the Linux and Windows plugins are kept: no Android, iOS, macOS or web
  code, so the Android app carries no ONNX Runtime.
- The build always downloads ONNX Runtime and bundles it, never a system one
  (which would not travel with the AppImage or the Windows zip).
- Linux bundles `libonnxruntime.so.1` itself. Upstream bundles the tarball's
  `libonnxruntime.so`, a symlink, which is copied as a symlink and left
  dangling in the app.
