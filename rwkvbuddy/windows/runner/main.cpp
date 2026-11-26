#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
// Keep the handle open for the lifetime of this GUI process. The OS closes it
// even after an abrupt exit, terminating the inherited Node/Lua process tree.
HANDLE CreateAgentProcessJob() {
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (!job) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits)) ||
      !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
    ::CloseHandle(job);
    ::OutputDebugStringW(L"TECNO Buddy: process job unavailable; graceful shutdown remains enabled.\n");
    return nullptr;
  }
  return job;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Do not close this handle manually while the app is running.
  const HANDLE agent_process_job = CreateAgentProcessJob();
  (void)agent_process_job;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"TECNO Buddy", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    // Scan-code-zero messages otherwise share Flutter physical key 0x1600000000.
    // Repair before TranslateMessage so the derived character uses the same key.
    // Keep IME process keys and Unicode packet input on their native path.
    if ((msg.message == WM_KEYDOWN || msg.message == WM_KEYUP ||
         msg.message == WM_SYSKEYDOWN || msg.message == WM_SYSKEYUP) &&
        (msg.lParam & 0x00ff0000) == 0 && msg.wParam != VK_PACKET &&
        msg.wParam != VK_PROCESSKEY) {
      const UINT scan_code = ::MapVirtualKeyExW(
          static_cast<UINT>(msg.wParam), MAPVK_VK_TO_VSC_EX,
          ::GetKeyboardLayout(0));
      if ((scan_code & 0xff) != 0) {
        msg.lParam |= static_cast<LPARAM>(scan_code & 0xff) << 16;
        // Windows maps the navigation cluster to the same low scan codes as
        // the numeric keypad; their extended flag is needed to distinguish them.
        const bool navigation_key =
            (msg.wParam >= VK_PRIOR && msg.wParam <= VK_DOWN) ||
            msg.wParam == VK_INSERT || msg.wParam == VK_DELETE;
        if ((scan_code & 0xff00) == 0xe000 || navigation_key) {
          msg.lParam |= static_cast<LPARAM>(1) << 24;
        }
      }
    }
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
