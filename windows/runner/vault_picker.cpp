#include "vault_picker.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <string>

void RegisterVaultPicker(flutter::BinaryMessenger* messenger, HWND owner) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "fptu_se_brain/vault",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [owner](const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "pickDirectory") {
          result->NotImplemented();
          return;
        }
        Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
        HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
        DWORD options = 0;
        if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
        if (SUCCEEDED(hr)) hr = dialog->SetOptions(options | FOS_PICKFOLDERS |
            FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
        if (SUCCEEDED(hr)) hr = dialog->SetTitle(L"Chon thu muc ghi chu (Vault)");
        if (SUCCEEDED(hr)) hr = dialog->Show(owner);
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
          result->Success(flutter::EncodableValue());
          return;
        }
        Microsoft::WRL::ComPtr<IShellItem> item;
        if (SUCCEEDED(hr)) hr = dialog->GetResult(item.GetAddressOf());
        PWSTR path = nullptr;
        if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        if (FAILED(hr)) {
          if (path) CoTaskMemFree(path);
          result->Error("picker_failed", "Cannot open vault folder dialog.");
          return;
        }
        const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
            path, -1, nullptr, 0, nullptr, nullptr);
        if (length <= 0) {
          CoTaskMemFree(path);
          result->Error("invalid_path", "Cannot decode the selected path.");
          return;
        }
        std::string utf8(static_cast<size_t>(length), '\0');
        const int written = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
            path, -1, utf8.data(), length, nullptr, nullptr);
        CoTaskMemFree(path);
        if (written <= 0) {
          result->Error("invalid_path", "Cannot decode the selected path.");
          return;
        }
        utf8.resize(static_cast<size_t>(written - 1));
        result->Success(flutter::EncodableValue(utf8));
      });
}
