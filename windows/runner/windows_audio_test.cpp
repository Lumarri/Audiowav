#include "windows_audio.h"
#include <audioclient.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <wrl.h>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>

namespace audiowav {
using Microsoft::WRL::ComPtr;
int WindowsAudio::TestTone() {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 1;
  int result = [&]() -> int {
    ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDevice> device;
    ComPtr<IAudioClient> client; ComPtr<IAudioRenderClient> render;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) ||
        FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) ||
        FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client))) return 2;
    WAVEFORMATEX format{WAVE_FORMAT_IEEE_FLOAT, 2, 48000, 48000 * 8, 8, 32, 0};
    if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
        400000, 0, &format, nullptr)) || FAILED(client->GetService(IID_PPV_ARGS(&render)))) return 3;
    UINT32 capacity = 0; client->GetBufferSize(&capacity);
    if (FAILED(client->Start())) return 4;
    const auto start = std::chrono::steady_clock::now(); uint64_t frame = 0;
    while (std::chrono::steady_clock::now() - start < std::chrono::seconds(30)) {
      UINT32 padding = 0; if (FAILED(client->GetCurrentPadding(&padding))) break;
      UINT32 count = capacity - padding;
      if (count) {
        BYTE* bytes = nullptr; if (FAILED(render->GetBuffer(count, &bytes))) break;
        auto* data = reinterpret_cast<float*>(bytes);
        for (UINT32 i = 0; i < count; ++i, ++frame) {
          const float sample = static_cast<float>(.002 * std::sin(frame * 2 * 3.14159265358979323846 * 440 / 48000));
          data[i * 2] = data[i * 2 + 1] = sample;
        }
        if (FAILED(render->ReleaseBuffer(count, 0))) break;
      }
      Sleep(5);
    }
    client->Stop(); return 0;
  }();
  CoUninitialize(); return result;
}
int WindowsAudio::SelfTest(const std::wstring& report) {
  std::ofstream log{std::filesystem::path(report)};
  if (!log) return 90;
  auto check = [&](bool ok, const char* text) { log << (ok ? "PASS " : "FAIL ") << text << std::endl; return ok; };
  auto wait = [](const std::function<bool()>& condition, int timeout = 12000) {
    const ULONGLONG end = GetTickCount64() + timeout;
    while (GetTickCount64() < end) { if (condition()) return true; Sleep(20); }
    return false;
  };
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (!check(SUCCEEDED(com), "COM initialization")) return 1;
  int result = [&]() -> int {
    DesktopSettings settings; settings.enabled = true;
    settings.reverb.enabled = true; settings.reverb.decay = .2f;
    settings.reverb.wet = .2f; settings.reverb.dry = .5f;
    auto fixture = std::filesystem::path(report); fixture += L".wav";
    {
      std::ofstream wave(fixture, std::ios::binary);
      const uint32_t rate = 44100, frames = rate * 3, size = frames * 2;
      const uint32_t riff = 36 + size, fmt_size = 16, bytes_per_sec = rate * 2;
      const uint16_t pcm = 1, channels = 1, align = 2, bits = 16;
      wave.write("RIFF", 4).write(reinterpret_cast<const char*>(&riff), 4).write("WAVEfmt ", 8);
      wave.write(reinterpret_cast<const char*>(&fmt_size), 4).write(reinterpret_cast<const char*>(&pcm), 2);
      wave.write(reinterpret_cast<const char*>(&channels), 2).write(reinterpret_cast<const char*>(&rate), 4);
      wave.write(reinterpret_cast<const char*>(&bytes_per_sec), 4).write(reinterpret_cast<const char*>(&align), 2);
      wave.write(reinterpret_cast<const char*>(&bits), 2).write("data", 4).write(reinterpret_cast<const char*>(&size), 4);
      for (uint32_t i = 0; i < frames; ++i) {
        int16_t sample = static_cast<int16_t>(40 * std::sin(i * 2 * 3.14159265358979323846 * 330 / rate));
        wave.write(reinterpret_cast<const char*>(&sample), 2);
      }
    }
    WindowsAudio local; local.Configure(settings); local.Open(fixture.wstring());
    if (!check(wait([&] { return local.Snapshot().position >= 200 || !local.Snapshot().error.empty(); }) &&
        local.Snapshot().error.empty(), "Media Foundation mono 44.1 kHz decode/resample -> stereo 48 kHz WASAPI")) {
      log << local.Snapshot().error << std::endl; local.Stop(); DeleteFile(fixture.c_str()); return 2;
    }
    local.Toggle(); Sleep(150); auto paused = local.Snapshot().position; Sleep(200);
    if (!check(std::abs(local.Snapshot().position - paused) < 40, "Pause holds source position")) return 3;
    local.Seek(1400);
    if (!check(wait([&] { return local.Snapshot().position >= 1390 && local.Snapshot().position <= 1410; }), "Seek while paused")) return 4;
    local.Toggle();
    if (!check(wait([&] { return local.Snapshot().position >= 1600; }), "Resume after seek")) return 5;
    local.Stop(); DeleteFile(fixture.c_str());
    wchar_t executable[32768]; GetModuleFileName(nullptr, executable, 32768);
    std::wstring command = L"\"" + std::wstring(executable) + L"\" --audio-test-tone";
    STARTUPINFO startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESHOWWINDOW; startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION child{};
    if (!check(CreateProcess(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &child) != FALSE,
        "Generated quiet tone in isolated child process")) return 6;
    int live_result = [&]() -> int {
      Sleep(400);
      WindowsAudio live; live.Configure(settings); live.StartApp(child.dwProcessId, "Audiowav test tone");
      if (!check(wait([&] { return live.Snapshot().muted || !live.Snapshot().error.empty(); }) && live.Snapshot().muted,
          "WASAPI process loopback and original session mute")) { log << live.Snapshot().error << ' ' << live.Snapshot().mute_error << std::endl; return 7; }
      Sleep(2500); auto state = live.Snapshot();
      if (!state.muted) wait([&] { return live.Snapshot().signal; }, 3000);
      state = live.Snapshot();
      const bool full = state.muted && state.signal && state.frames > 48000;
      const bool fallback = !state.muted && state.signal && !state.mute_error.empty() && state.frames > 48000;
      if (!check(full || fallback, full ? "Signal continues while original muted; full DRY/WET" :
          "Capture resumes after restoring original; WET fallback avoids dry duplication")) {
        log << state.error << ' ' << state.mute_error << " signal=" << state.signal << " frames=" << state.frames << std::endl; return 8;
      }
      log << "Process capture route=" << (full ? "full DRY/WET" : "WET return (session mute also silences capture)") << std::endl;
      log << "frames=" << state.frames << " maxBlockUs=" << state.max_micros << " underruns=" << state.underruns << std::endl;
      live.Stop();
      ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDevice> device;
      ComPtr<IAudioSessionManager2> manager; ComPtr<IAudioSessionEnumerator> sessions;
      bool restored = false;
      if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) &&
          SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) &&
          SUCCEEDED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, &manager)) &&
          SUCCEEDED(manager->GetSessionEnumerator(&sessions))) {
        int count = 0; sessions->GetCount(&count);
        for (int i = 0; i < count; ++i) {
          ComPtr<IAudioSessionControl> control; ComPtr<IAudioSessionControl2> control2; ComPtr<ISimpleAudioVolume> volume;
          DWORD pid = 0; BOOL muted = TRUE;
          if (SUCCEEDED(sessions->GetSession(i, &control)) && SUCCEEDED(control.As(&control2)) &&
              SUCCEEDED(control2->GetProcessId(&pid)) && pid == child.dwProcessId && SUCCEEDED(control.As(&volume)) &&
              SUCCEEDED(volume->GetMute(&muted))) restored = muted == FALSE;
        }
      }
      return check(restored, "Stop restores the original session mute state") ? 0 : 9;
    }();
    TerminateProcess(child.hProcess, 0); WaitForSingleObject(child.hProcess, 3000);
    CloseHandle(child.hThread); CloseHandle(child.hProcess);
    return live_result;
  }();
  CoUninitialize(); log << "Result=" << result << std::endl;
  return result;
}
}
