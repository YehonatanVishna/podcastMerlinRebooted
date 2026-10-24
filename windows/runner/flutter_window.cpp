#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>
#include <windows.h>
#include <wlanapi.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include "flutter/generated_plugin_registrant.h"

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

  auto network_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.podcastmerlin.app/network",
      &flutter::StandardMethodCodec::GetInstance());
  network_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getNetworkInfo") {
          std::string ssid_str = "";
          bool is_wifi = false;

          HANDLE client_handle = nullptr;
          DWORD cur_version = 0;
          if (WlanOpenHandle(2, nullptr, &cur_version, &client_handle) == ERROR_SUCCESS) {
            PWLAN_INTERFACE_INFO_LIST if_list = nullptr;
            if (WlanEnumInterfaces(client_handle, nullptr, &if_list) == ERROR_SUCCESS) {
              for (DWORD i = 0; i < if_list->dwNumberOfItems; ++i) {
                PWLAN_CONNECTION_ATTRIBUTES conn_attr = nullptr;
                DWORD data_size = sizeof(WLAN_CONNECTION_ATTRIBUTES);
                WLAN_OPCODE_VALUE_TYPE op_code;
                if (WlanQueryInterface(client_handle, &if_list->InterfaceInfo[i].InterfaceGuid,
                                       wlan_intf_opcode_current_connection, nullptr, &data_size,
                                       (PVOID*)&conn_attr, &op_code) == ERROR_SUCCESS) {
                  is_wifi = true;
                  DOT11_SSID dot11_ssid = conn_attr->wlanAssociationAttributes.dot11Ssid;
                  if (dot11_ssid.uSSIDLength > 0) {
                    ssid_str = std::string(reinterpret_cast<char*>(dot11_ssid.ucSSID),
                                           dot11_ssid.uSSIDLength);
                  }
                  WlanFreeMemory(conn_attr);
                  if (!ssid_str.empty()) break;
                }
              }
              WlanFreeMemory(if_list);
            }
            WlanCloseHandle(client_handle, nullptr);
          }

          flutter::EncodableMap response;
          response[flutter::EncodableValue("isConnected")] = flutter::EncodableValue(true);
          response[flutter::EncodableValue("isWifi")] = flutter::EncodableValue(is_wifi || !ssid_str.empty());
          response[flutter::EncodableValue("isEthernet")] = flutter::EncodableValue(false);
          response[flutter::EncodableValue("isCellular")] = flutter::EncodableValue(false);
          if (!ssid_str.empty()) {
            response[flutter::EncodableValue("ssid")] = flutter::EncodableValue(ssid_str);
          } else {
            response[flutter::EncodableValue("ssid")] = flutter::EncodableValue();
          }
          result->Success(flutter::EncodableValue(response));
        } else {
          result->NotImplemented();
        }
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

void FlutterWindow::OnDestroy() {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
