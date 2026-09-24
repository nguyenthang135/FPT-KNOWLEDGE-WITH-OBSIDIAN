#include "obsidian_desktop.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cwctype>
#include <sstream>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace {

enum class HostState { kIdle, kLaunching, kHosted, kFailed };

struct HostSession {
  HWND owner = nullptr;
  HWND flutter_view = nullptr;
  HWND host = nullptr;
  HWND obsidian = nullptr;
  HWND original_parent = nullptr;
  LONG_PTR original_style = 0;
  LONG_PTR original_ex_style = 0;
  RECT original_rect{};
  RECT bounds{};
  DWORD launched_process_id = 0;
  ULONGLONG launch_started_at = 0;
  std::set<HWND> existing_obsidian_windows;
  std::wstring executable_path;
  std::wstring vault_path;
  std::wstring file_path;
  std::wstring expected_vault_name;
  HostState state = HostState::kIdle;
  std::string message = "Obsidian host is idle.";
};

HostSession g_session;

constexpr wchar_t kHostWindowClass[] = L"FPTKnowledgeObsidianHost";
constexpr UINT kFocusObsidianMessage = WM_APP + 0x3A1;

bool FocusHostedObsidian(const char* reason);

LRESULT CALLBACK HostWindowProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      PostMessageW(window, kFocusObsidianMessage, 0, 0);
      return MA_ACTIVATE;
    case WM_SETFOCUS:
      PostMessageW(window, kFocusObsidianMessage, 0, 0);
      return 0;
    case kFocusObsidianMessage:
      FocusHostedObsidian("host activation");
      return 0;
    default:
      return DefWindowProcW(window, message, wparam, lparam);
  }
}

bool EnsureHostWindowClass() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = HostWindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kHostWindowClass;

  return RegisterClassW(&window_class) != 0 ||
         GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool RegistryKeyExists(HKEY root, const wchar_t* path) {
  HKEY key = nullptr;
  const LONG result = RegOpenKeyExW(root, path, 0, KEY_READ, &key);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  RegCloseKey(key);
  return true;
}

std::wstring ReadRegistryString(HKEY root, const wchar_t* path) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return L"";
  }

  DWORD type = 0;
  DWORD byte_count = 0;
  LONG result = RegQueryValueExW(key, nullptr, nullptr, &type, nullptr,
                                 &byte_count);
  if (result != ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ) || byte_count == 0) {
    RegCloseKey(key);
    return L"";
  }

  std::vector<wchar_t> buffer(byte_count / sizeof(wchar_t) + 1, L'\0');
  result = RegQueryValueExW(key, nullptr, nullptr, &type,
                            reinterpret_cast<LPBYTE>(buffer.data()),
                            &byte_count);
  RegCloseKey(key);

  if (result != ERROR_SUCCESS) {
    return L"";
  }

  return std::wstring(buffer.data());
}

std::wstring EnvironmentPath(const wchar_t* name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required == 0) {
    return L"";
  }

  std::wstring value(required, L'\0');
  const DWORD written =
      GetEnvironmentVariableW(name, value.data(), required);
  if (written == 0 || written >= required) {
    return L"";
  }

  value.resize(written);
  return value;
}

bool FileExists(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }

  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool DirectoryExists(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }

  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

std::wstring ExtractExecutable(const std::wstring& command) {
  if (command.empty()) {
    return L"";
  }

  const size_t first = command.find_first_not_of(L" \t");
  if (first == std::wstring::npos) {
    return L"";
  }

  if (command[first] == L'\"') {
    const size_t closing = command.find(L'\"', first + 1);
    return closing == std::wstring::npos
               ? L""
               : command.substr(first + 1, closing - first - 1);
  }

  const size_t closing = command.find_first_of(L" \t", first);
  return command.substr(first, closing - first);
}

std::wstring FindObsidianExecutable() {
  const std::array<std::wstring, 4> candidates = {
      EnvironmentPath(L"LOCALAPPDATA") + L"\\Obsidian\\Obsidian.exe",
      EnvironmentPath(L"LOCALAPPDATA") +
          L"\\Programs\\Obsidian\\Obsidian.exe",
      EnvironmentPath(L"ProgramFiles") + L"\\Obsidian\\Obsidian.exe",
      EnvironmentPath(L"ProgramFiles(x86)") + L"\\Obsidian\\Obsidian.exe",
  };

  for (const auto& candidate : candidates) {
    if (FileExists(candidate)) {
      return candidate;
    }
  }

  const std::array<std::pair<HKEY, const wchar_t*>, 2> protocol_keys = {{
      {HKEY_CURRENT_USER,
       L"Software\\Classes\\obsidian\\shell\\open\\command"},
      {HKEY_CLASSES_ROOT, L"obsidian\\shell\\open\\command"},
  }};

  for (const auto& key : protocol_keys) {
    const std::wstring executable =
        ExtractExecutable(ReadRegistryString(key.first, key.second));
    if (FileExists(executable)) {
      return executable;
    }
  }

  return L"";
}

bool IsObsidianInstalled() {
  return !FindObsidianExecutable().empty() ||
         RegistryKeyExists(
             HKEY_CURRENT_USER,
             L"Software\\Classes\\obsidian\\shell\\open\\command") ||
         RegistryKeyExists(HKEY_CLASSES_ROOT,
                           L"obsidian\\shell\\open\\command") ||
         RegistryKeyExists(
             HKEY_CURRENT_USER,
             L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Obsidian") ||
         RegistryKeyExists(
             HKEY_LOCAL_MACHINE,
             L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Obsidian") ||
         RegistryKeyExists(
             HKEY_LOCAL_MACHINE,
             L"Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Obsidian");
}

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) { return towlower(character); });
  return value;
}

std::wstring BaseName(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? path : path.substr(separator + 1);
}

std::wstring WindowTitle(HWND window) {
  const int length = GetWindowTextLengthW(window);
  if (length <= 0) {
    return L"";
  }

  std::wstring title(static_cast<size_t>(length) + 1, L'\0');
  GetWindowTextW(window, title.data(), length + 1);
  title.resize(static_cast<size_t>(length));
  return title;
}

std::wstring ProcessPath(DWORD process_id) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) {
    return L"";
  }

  std::wstring path(32768, L'\0');
  DWORD length = static_cast<DWORD>(path.size());
  const BOOL success =
      QueryFullProcessImageNameW(process, 0, path.data(), &length);
  CloseHandle(process);

  if (!success) {
    return L"";
  }

  path.resize(length);
  return path;
}

bool IsObsidianWindow(HWND window, DWORD* process_id_out = nullptr) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0) {
    return false;
  }

  const std::wstring process_path = ProcessPath(process_id);
  if (process_path.empty()) {
    return false;
  }

  const bool matches = !g_session.executable_path.empty()
                           ? Lower(process_path) ==
                                 Lower(g_session.executable_path)
                           : Lower(BaseName(process_path)) == L"obsidian.exe";

  if (matches && process_id_out != nullptr) {
    *process_id_out = process_id;
  }

  return matches;
}

BOOL CALLBACK CollectObsidianWindows(HWND window, LPARAM parameter) {
  auto* windows = reinterpret_cast<std::set<HWND>*>(parameter);
  if (IsObsidianWindow(window)) {
    windows->insert(window);
  }
  return TRUE;
}

std::set<HWND> CurrentObsidianWindows() {
  std::set<HWND> windows;
  EnumWindows(CollectObsidianWindows,
              reinterpret_cast<LPARAM>(&windows));
  return windows;
}

std::wstring UriEncode(const std::wstring& value) {
  if (value.empty()) {
    return L"";
  }

  const int required = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1,
                                            nullptr, 0, nullptr, nullptr);
  if (required <= 1) {
    return L"";
  }

  std::string utf8(static_cast<size_t>(required), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, utf8.data(), required,
                      nullptr, nullptr);
  utf8.resize(static_cast<size_t>(required) - 1);

  constexpr wchar_t kHex[] = L"0123456789ABCDEF";
  std::wstring encoded;
  for (const unsigned char byte : utf8) {
    if (std::isalnum(byte) || byte == '-' || byte == '_' || byte == '.' ||
        byte == '~') {
      encoded.push_back(static_cast<wchar_t>(byte));
    } else {
      encoded.push_back(L'%');
      encoded.push_back(kHex[(byte >> 4) & 0x0F]);
      encoded.push_back(kHex[byte & 0x0F]);
    }
  }
  return encoded;
}

bool IsHostedObsidianWindow(HWND window) {
  return IsWindow(g_session.obsidian) && IsWindow(window) &&
         (window == g_session.obsidian || IsChild(g_session.obsidian, window));
}

struct FocusTargetSearch {
  HWND renderer = nullptr;
};

BOOL CALLBACK FindFocusTarget(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<FocusTargetSearch*>(parameter);
  if (!IsWindowVisible(window) || !IsWindowEnabled(window)) {
    return TRUE;
  }

  std::array<wchar_t, 256> class_name{};
  GetClassNameW(window, class_name.data(),
                static_cast<int>(class_name.size()));
  if (Lower(class_name.data()) == L"chrome_renderwidgethosthwnd") {
    search->renderer = window;
    return FALSE;
  }

  return TRUE;
}

HWND ObsidianFocusTarget() {
  if (!IsWindow(g_session.obsidian)) {
    return nullptr;
  }

  DWORD process_id = 0;
  const DWORD thread_id =
      GetWindowThreadProcessId(g_session.obsidian, &process_id);
  GUITHREADINFO thread_info{};
  thread_info.cbSize = sizeof(thread_info);
  if (thread_id != 0 && GetGUIThreadInfo(thread_id, &thread_info) &&
      IsHostedObsidianWindow(thread_info.hwndFocus)) {
    return thread_info.hwndFocus;
  }

  FocusTargetSearch search;
  EnumChildWindows(g_session.obsidian, FindFocusTarget,
                   reinterpret_cast<LPARAM>(&search));
  return IsWindow(search.renderer) ? search.renderer : g_session.obsidian;
}

std::string DescribeWindow(HWND window) {
  if (!IsWindow(window)) {
    return "none";
  }

  std::array<char, 256> class_name{};
  GetClassNameA(window, class_name.data(),
                static_cast<int>(class_name.size()));
  DWORD process_id = 0;
  const DWORD thread_id = GetWindowThreadProcessId(window, &process_id);

  std::ostringstream description;
  description << "0x" << std::hex
              << reinterpret_cast<std::uintptr_t>(window) << std::dec << "["
              << class_name.data() << ",tid=" << thread_id
              << ",pid=" << process_id << "]";
  return description.str();
}

void LogFocusState(const char* reason, HWND target) {
  DWORD obsidian_process_id = 0;
  const DWORD obsidian_thread_id = IsWindow(g_session.obsidian)
                                       ? GetWindowThreadProcessId(
                                             g_session.obsidian,
                                             &obsidian_process_id)
                                       : 0;
  GUITHREADINFO thread_info{};
  thread_info.cbSize = sizeof(thread_info);
  HWND obsidian_focus = nullptr;
  if (obsidian_thread_id != 0 &&
      GetGUIThreadInfo(obsidian_thread_id, &thread_info)) {
    obsidian_focus = thread_info.hwndFocus;
  }

  std::ostringstream message;
  message << "[ObsidianHost] " << reason
          << " foreground=" << DescribeWindow(GetForegroundWindow())
          << " active=" << DescribeWindow(GetActiveWindow())
          << " callerFocus=" << DescribeWindow(GetFocus())
          << " obsidianFocus=" << DescribeWindow(obsidian_focus)
          << " target=" << DescribeWindow(target) << "\n";
  const std::string text = message.str();
  OutputDebugStringA(text.c_str());
  std::fputs(text.c_str(), stderr);
  std::fflush(stderr);
}

bool FocusHostedObsidian(const char* reason) {
  HWND target = ObsidianFocusTarget();
  if (!IsWindow(target)) {
    return false;
  }

  LogFocusState("before focus transfer", target);

  const DWORD caller_thread_id = GetCurrentThreadId();
  const DWORD target_thread_id = GetWindowThreadProcessId(target, nullptr);
  const HWND foreground_window = GetForegroundWindow();
  const DWORD foreground_thread_id = IsWindow(foreground_window)
                                         ? GetWindowThreadProcessId(
                                               foreground_window, nullptr)
                                         : 0;

  const bool attached_target =
      target_thread_id != 0 && target_thread_id != caller_thread_id &&
      AttachThreadInput(caller_thread_id, target_thread_id, TRUE) != FALSE;
  const bool attached_foreground =
      foreground_thread_id != 0 &&
      foreground_thread_id != caller_thread_id &&
      foreground_thread_id != target_thread_id &&
      AttachThreadInput(caller_thread_id, foreground_thread_id, TRUE) != FALSE;

  SetForegroundWindow(g_session.owner);
  SetActiveWindow(g_session.owner);
  BringWindowToTop(g_session.owner);
  SetLastError(ERROR_SUCCESS);
  const HWND previous_focus = SetFocus(target);
  const bool focus_call_succeeded = previous_focus != nullptr ||
                                    GetLastError() == ERROR_SUCCESS;

  if (attached_foreground) {
    AttachThreadInput(caller_thread_id, foreground_thread_id, FALSE);
  }
  if (attached_target) {
    AttachThreadInput(caller_thread_id, target_thread_id, FALSE);
  }

  LogFocusState(reason, target);

  GUITHREADINFO target_info{};
  target_info.cbSize = sizeof(target_info);
  return focus_call_succeeded &&
         GetGUIThreadInfo(target_thread_id, &target_info) &&
         IsHostedObsidianWindow(target_info.hwndFocus);
}

bool EnsureHostWindow() {
  if (IsWindow(g_session.host)) {
    return true;
  }

  if (!EnsureHostWindowClass()) {
    g_session.state = HostState::kFailed;
    g_session.message = "Could not register the native Obsidian host area.";
    return false;
  }

  g_session.host = CreateWindowExW(
      0, kHostWindowClass, L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
      g_session.bounds.left, g_session.bounds.top,
      g_session.bounds.right - g_session.bounds.left,
      g_session.bounds.bottom - g_session.bounds.top, g_session.flutter_view,
      nullptr, GetModuleHandleW(nullptr), nullptr);

  if (!IsWindow(g_session.host)) {
    g_session.state = HostState::kFailed;
    g_session.message = "Could not create the native Obsidian host area.";
    return false;
  }

  return true;
}

void ResizeHostedWindow() {
  if (!IsWindow(g_session.host)) {
    return;
  }

  const int width = std::max(
      1, static_cast<int>(g_session.bounds.right - g_session.bounds.left));
  const int height = std::max(
      1, static_cast<int>(g_session.bounds.bottom - g_session.bounds.top));
  SetWindowPos(g_session.host, HWND_TOP, g_session.bounds.left,
               g_session.bounds.top, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);

  if (IsWindow(g_session.obsidian)) {
    SetWindowPos(g_session.obsidian, HWND_TOP, 0, 0, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }
}

void ReleaseHostedWindow(bool close_window) {
  if (!IsWindow(g_session.obsidian)) {
    g_session.obsidian = nullptr;
    return;
  }

  ShowWindow(g_session.obsidian, SW_HIDE);
  SetParent(g_session.obsidian, g_session.original_parent);
  SetWindowLongPtrW(g_session.obsidian, GWL_STYLE, g_session.original_style);
  SetWindowLongPtrW(g_session.obsidian, GWL_EXSTYLE,
                    g_session.original_ex_style);
  UINT position_flags = SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE;
  if (!close_window) {
    position_flags |= SWP_SHOWWINDOW;
  }
  SetWindowPos(g_session.obsidian, nullptr, g_session.original_rect.left,
               g_session.original_rect.top,
               g_session.original_rect.right - g_session.original_rect.left,
               g_session.original_rect.bottom - g_session.original_rect.top,
               position_flags);

  if (close_window) {
    PostMessageW(g_session.obsidian, WM_CLOSE, 0, 0);
  }

  g_session.obsidian = nullptr;
}

bool AttachWindow(HWND window) {
  if (!IsWindow(window) || !EnsureHostWindow()) {
    return false;
  }

  g_session.obsidian = window;
  g_session.original_parent = GetParent(window);
  g_session.original_style = GetWindowLongPtrW(window, GWL_STYLE);
  g_session.original_ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  GetWindowRect(window, &g_session.original_rect);

  ShowWindow(window, SW_HIDE);
  const LONG_PTR hosted_style =
      (g_session.original_style &
       ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX |
         WS_MAXIMIZEBOX)) |
      WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  SetWindowLongPtrW(window, GWL_STYLE, hosted_style);
  SetWindowLongPtrW(window, GWL_EXSTYLE,
                    (g_session.original_ex_style & ~WS_EX_APPWINDOW) |
                        WS_EX_TOOLWINDOW);

  SetLastError(ERROR_SUCCESS);
  if (SetParent(window, g_session.host) == nullptr &&
      GetLastError() != ERROR_SUCCESS) {
    ReleaseHostedWindow(false);
    g_session.state = HostState::kFailed;
    g_session.message = "Windows rejected the Obsidian reparenting request.";
    return false;
  }

  g_session.state = HostState::kHosted;
  g_session.message = "Obsidian is hosted inside My Notes.";
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  ResizeHostedWindow();
  ShowWindow(g_session.host, SW_SHOW);
  ShowWindow(window, SW_SHOW);
  FocusHostedObsidian("after attach");
  return true;
}

void CloseNewLaunchedWindows() {
  if (g_session.launched_process_id == 0) {
    return;
  }

  for (const HWND window : CurrentObsidianWindows()) {
    if (g_session.existing_obsidian_windows.count(window) != 0) {
      continue;
    }

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (process_id == g_session.launched_process_id) {
      PostMessageW(window, WM_CLOSE, 0, 0);
    }
  }
}

void TryAttachNewWindow() {
  if (g_session.state != HostState::kLaunching) {
    return;
  }

  for (const HWND window : CurrentObsidianWindows()) {
    if (g_session.existing_obsidian_windows.count(window) != 0 ||
        !IsWindowVisible(window)) {
      continue;
    }

    const std::wstring title = Lower(WindowTitle(window));
    if (title.find(Lower(g_session.expected_vault_name)) ==
        std::wstring::npos) {
      continue;
    }

    if (AttachWindow(window)) {
      return;
    }
  }

  if (GetTickCount64() - g_session.launch_started_at > 20000) {
    CloseNewLaunchedWindows();
    if (IsWindow(g_session.host)) {
      ShowWindow(g_session.host, SW_HIDE);
    }
    g_session.state = HostState::kFailed;
    g_session.message =
        "Obsidian did not create a new window for this FPT Knowledge vault. "
        "Open the generated FPT Knowledge folder as an Obsidian vault once, "
        "then retry. Existing Obsidian windows were not touched.";
  }
}

bool LaunchObsidian(const std::wstring& vault_path,
                    const std::wstring& file_path) {
  g_session.executable_path = FindObsidianExecutable();
  g_session.existing_obsidian_windows = CurrentObsidianWindows();
  g_session.launched_process_id = 0;

  // Obsidian normally runs as a single instance. Sending a vault URI while an
  // unrelated window exists can navigate that window instead of creating a
  // dedicated one, so fail safely rather than altering or reparenting it.
  if (!g_session.existing_obsidian_windows.empty()) {
    g_session.state = HostState::kFailed;
    g_session.message =
        "A separate Obsidian window is already open. Obsidian cannot "
        "reliably guarantee a dedicated window for this vault, so the "
        "existing window was left untouched. Close it and retry hosting.";
    return false;
  }

  const std::wstring target = file_path.empty() ? vault_path : file_path;
  const std::wstring uri = L"obsidian://open?path=" + UriEncode(target);
  bool launched = false;

  if (!g_session.executable_path.empty()) {
    std::wstring command = L"\"" + g_session.executable_path + L"\" \"" +
                           uri + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    launched = CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                              0, nullptr, nullptr, &startup, &process) != FALSE;
    if (launched) {
      g_session.launched_process_id = process.dwProcessId;
      CloseHandle(process.hThread);
      CloseHandle(process.hProcess);
    }
  }

  if (!launched) {
    const HINSTANCE result = ShellExecuteW(g_session.owner, L"open", uri.c_str(),
                                           nullptr, nullptr, SW_SHOWNORMAL);
    launched = reinterpret_cast<INT_PTR>(result) > 32;
  }

  if (!launched) {
    g_session.state = HostState::kFailed;
    g_session.message = "Could not launch Obsidian for the FPT Knowledge vault.";
    return false;
  }

  g_session.launch_started_at = GetTickCount64();
  g_session.state = HostState::kLaunching;
  g_session.message = "Waiting for a dedicated FPT Knowledge Obsidian window...";
  return true;
}

const flutter::EncodableMap* Arguments(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (call.arguments() == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

const flutter::EncodableValue* Argument(const flutter::EncodableMap& map,
                                        const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

int ArgumentInt(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Argument(map, key);
  if (value == nullptr) {
    return 0;
  }
  if (const auto* integer = std::get_if<int32_t>(value)) {
    return *integer;
  }
  if (const auto* integer = std::get_if<int64_t>(value)) {
    return static_cast<int>(*integer);
  }
  if (const auto* number = std::get_if<double>(value)) {
    return static_cast<int>(*number);
  }
  return 0;
}

std::string ArgumentString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Argument(map, key);
  if (value == nullptr) {
    return "";
  }
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? "" : *text;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }

  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            value.c_str(), -1, nullptr, 0);
  if (required <= 1) {
    return L"";
  }

  std::wstring wide(static_cast<size_t>(required), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1,
                      wide.data(), required);
  wide.resize(static_cast<size_t>(required) - 1);
  return wide;
}

std::string StateName() {
  switch (g_session.state) {
    case HostState::kLaunching:
      return "launching";
    case HostState::kHosted:
      return "hosted";
    case HostState::kFailed:
      return "failed";
    case HostState::kIdle:
    default:
      return "idle";
  }
}

flutter::EncodableValue StatusValue() {
  if (g_session.state == HostState::kHosted &&
      !IsWindow(g_session.obsidian)) {
    g_session.obsidian = nullptr;
    if (IsWindow(g_session.host)) {
      ShowWindow(g_session.host, SW_HIDE);
    }
    g_session.state = HostState::kFailed;
    g_session.message = "The hosted Obsidian window closed or crashed.";
  }

  TryAttachNewWindow();

  flutter::EncodableMap status;
  status[flutter::EncodableValue("state")] =
      flutter::EncodableValue(StateName());
  status[flutter::EncodableValue("message")] =
      flutter::EncodableValue(g_session.message);
  return flutter::EncodableValue(status);
}

void UpdateBounds(const flutter::EncodableMap& arguments) {
  const int x = ArgumentInt(arguments, "x");
  const int y = ArgumentInt(arguments, "y");
  const int width = std::max(1, ArgumentInt(arguments, "width"));
  const int height = std::max(1, ArgumentInt(arguments, "height"));
  g_session.bounds = {x, y, x + width, y + height};
  ResizeHostedWindow();
}

}  // namespace

void RegisterObsidianDesktop(flutter::BinaryMessenger* messenger, HWND owner,
                             HWND flutter_view) {
  g_session.owner = owner;
  g_session.flutter_view = flutter_view;

  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "fptu_se_brain/obsidian_desktop",
      &flutter::StandardMethodCodec::GetInstance());

  channel.SetMethodCallHandler(
      [owner](const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result) {
        if (call.method_name() == "isInstalled") {
          result->Success(flutter::EncodableValue(IsObsidianInstalled()));
          return;
        }

        if (call.method_name() == "openDownloadPage") {
          const HINSTANCE opened = ShellExecuteW(
              owner, L"open", L"https://obsidian.md/download", nullptr, nullptr,
              SW_SHOWNORMAL);
          if (reinterpret_cast<INT_PTR>(opened) <= 32) {
            result->Error("open_failed",
                          "Could not open the Obsidian download page.");
          } else {
            result->Success();
          }
          return;
        }

        if (call.method_name() == "startHosting") {
          const auto* arguments = Arguments(call);
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "Host arguments are required.");
            return;
          }

          const std::wstring vault_path =
              Utf8ToWide(ArgumentString(*arguments, "vaultPath"));
          if (!DirectoryExists(vault_path)) {
            result->Error("vault_missing",
                          "The generated FPT Knowledge vault does not exist.");
            return;
          }
          const std::wstring file_path =
              Utf8ToWide(ArgumentString(*arguments, "filePath"));
          const std::wstring vault_prefix = Lower(vault_path + L"\\");
          if (!FileExists(file_path) ||
              Lower(file_path).rfind(vault_prefix, 0) != 0) {
            result->Error(
                "note_missing",
                "The selected My Notes file is missing or outside the vault.");
            return;
          }

          UpdateBounds(*arguments);

          if (g_session.state == HostState::kHosted &&
              IsWindow(g_session.obsidian) &&
              Lower(g_session.vault_path) == Lower(vault_path)) {
            if (Lower(g_session.file_path) != Lower(file_path)) {
              const std::wstring uri =
                  L"obsidian://open?path=" + UriEncode(file_path);
              ShellExecuteW(g_session.owner, L"open", uri.c_str(), nullptr,
                            nullptr, SW_SHOWNORMAL);
              g_session.file_path = file_path;
            }
            ShowWindow(g_session.host, SW_SHOW);
            ShowWindow(g_session.obsidian, SW_SHOW);
            ResizeHostedWindow();
            FocusHostedObsidian("host restored");
            result->Success(StatusValue());
            return;
          }

          if (IsWindow(g_session.obsidian)) {
            ReleaseHostedWindow(true);
          }

          g_session.vault_path = vault_path;
          g_session.file_path = file_path;
          g_session.expected_vault_name = BaseName(vault_path);
          if (!EnsureHostWindow()) {
            result->Success(StatusValue());
            return;
          }
          ShowWindow(g_session.host, SW_HIDE);
          LaunchObsidian(vault_path, file_path);
          result->Success(StatusValue());
          return;
        }

        if (call.method_name() == "updateHostBounds") {
          const auto* arguments = Arguments(call);
          if (arguments != nullptr) {
            UpdateBounds(*arguments);
          }
          result->Success(StatusValue());
          return;
        }

        if (call.method_name() == "getHostStatus") {
          result->Success(StatusValue());
          return;
        }

        if (call.method_name() == "hideHost") {
          if (IsWindow(g_session.obsidian)) {
            ShowWindow(g_session.obsidian, SW_HIDE);
          }
          if (IsWindow(g_session.host)) {
            ShowWindow(g_session.host, SW_HIDE);
          }
          result->Success();
          return;
        }

        if (call.method_name() == "focusHost") {
          if (IsWindow(g_session.obsidian)) {
            FocusHostedObsidian("focusHost request");
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void ShutdownObsidianDesktop() {
  ReleaseHostedWindow(true);
  if (IsWindow(g_session.host)) {
    DestroyWindow(g_session.host);
  }
  g_session = HostSession{};
}
