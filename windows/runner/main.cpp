#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "windows_audio.h"
#include <shellapi.h>

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argc >= 2 && std::wstring(argv[1]) == L"--audio-guard" && argc == 5) {
    const int result = audiowav::WindowsAudio::RestoreGuard(wcstoul(argv[2], nullptr, 10), argv[3], argv[4]);
    LocalFree(argv); return result;
  }
  if (argc == 2 && std::wstring(argv[1]) == L"--audio-test-tone") {
    LocalFree(argv); return audiowav::WindowsAudio::TestTone();
  }
  if (argc == 3 && std::wstring(argv[1]) == L"--audio-self-test") {
    const std::wstring report = argv[2]; LocalFree(argv);
    return audiowav::WindowsAudio::SelfTest(report);
  }
  LocalFree(argv);
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Audiowav · Estudio de audio para Windows", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
