#pragma once
#include <windows.h>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "audio_dsp.h"

namespace audiowav {
struct AudioApp { DWORD pid = 0; std::string name; };
struct AudioDevice { std::wstring id; std::string name; bool virtual_cable = false; };
struct DesktopState {
  bool running = false, ready = false, playing = false, has_file = false;
  bool live = false, muted = false, signal = false, tail = false;
  int64_t position = 0, duration = 0, frames = 0, max_micros = 0;
  int64_t underruns = 0, discontinuities = 0, limited = 0;
  float peak = 0;
  DWORD pid = 0;
  std::string title, error, mute_error, device;
};

class WindowsAudio {
 public:
  WindowsAudio() = default;
  ~WindowsAudio();
  void Configure(DesktopSettings settings);
  void Open(const std::wstring& path);
  void StartApp(DWORD pid, std::string label);
  void StartCable(const std::wstring& id, std::string label);
  void SelectOutput(const std::wstring& id);
  void Stop();
  void Toggle();
  void Seek(int64_t milliseconds);
  DesktopState Snapshot();
  static std::vector<AudioApp> Apps();
  static std::vector<AudioDevice> Devices();
  static float Volume();
  static void Volume(float level);
  static int SelfTest(const std::wstring& report);
  static int TestTone();
  static int RestoreGuard(DWORD parent, const std::wstring& event, const std::wstring& journal);
 private:
  void Run(std::wstring path, DWORD pid, bool cable);
  std::mutex mutex_;
  DesktopSettings settings_;
  DesktopState state_;
  std::wstring output_id_;
  uint64_t revision_ = 0;
  std::thread worker_;
  std::atomic<bool> stop_{false}, paused_{false};
  std::atomic<int64_t> seek_{-1};
};
std::string Utf8(const std::wstring& value);
std::wstring Wide(const std::string& value);
}
