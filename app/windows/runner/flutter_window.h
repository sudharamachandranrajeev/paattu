#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "dev.paattu.paattu/window": the title bar in the app's colours
  // (lib/src/ui/title_bar.dart).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;

  // The colours last asked for (0x00RRGGBB), put back when Windows redraws
  // the frame in its own after a theme change; caption < 0 for none yet.
  int caption_ = -1;
  int text_ = 0;
  int border_ = 0;
  bool dark_ = false;

  void ApplyTitleBar();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
