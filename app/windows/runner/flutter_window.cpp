#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// Windows 11's frame colours, for SDKs from before them.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

namespace {

// 0x00RRGGBB as Windows wants it (0x00BBGGRR).
COLORREF ToColorRef(int rgb) {
  return RGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
}

// An int from the map, or |fallback| when it's missing or not one.
int IntArg(const flutter::EncodableMap& args, const char* key, int fallback) {
  auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "dev.paattu.paattu/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() != "setTitleBar" || args == nullptr) {
          result->NotImplemented();
          return;
        }
        caption_ = IntArg(*args, "caption", -1) & 0xffffff;
        text_ = IntArg(*args, "text", 0xffffff) & 0xffffff;
        border_ = IntArg(*args, "border", caption_) & 0xffffff;
        auto dark = args->find(flutter::EncodableValue("dark"));
        const bool* is_dark = dark == args->end() ? nullptr : std::get_if<bool>(&dark->second);
        dark_ = is_dark != nullptr && *is_dark;
        ApplyTitleBar();
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ApplyTitleBar() {
  HWND window = GetHandle();
  if (window == nullptr || caption_ < 0) return;
  // Each is left as it was where Windows doesn't know it (Windows 10 knows
  // only the dark frame).
  BOOL dark = dark_ ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
  COLORREF caption = ToColorRef(caption_);
  COLORREF text = ToColorRef(text_);
  COLORREF border = ToColorRef(border_);
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &text, sizeof(text));
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DWMCOLORIZATIONCOLORCHANGED: {
      // Windows puts its own dark or light frame back (Win32Window::
      // UpdateTheme); the app's colours go back over it.
      LRESULT handled = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      ApplyTitleBar();
      return handled;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
