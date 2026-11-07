#include "windows_audio.h"
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <audiopolicy.h>
#include <avrt.h>
#include <endpointvolume.h>
#include <propsys.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <wrl.h>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <cmath>
#include <fstream>
#include <filesystem>
#include <iomanip>
#include <sstream>

using Microsoft::WRL::ComPtr;
namespace audiowav {
namespace {
constexpr UINT32 rate = 48000;
constexpr int block_frames = 480;
constexpr DWORD audio_stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
using Clock = std::chrono::steady_clock;
#define AW_CHECK(call) do { const HRESULT aw_hr = (call); if (FAILED(aw_hr)) return aw_hr; } while (false)
struct ComScope {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ~ComScope() { if (SUCCEEDED(hr)) CoUninitialize(); }
};
struct Event {
  HANDLE value = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  ~Event() { if (value) CloseHandle(value); }
};
ComPtr<IMMDevice> DefaultDevice() {
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      IID_PPV_ARGS(&enumerator)))) enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  return device;
}
ComPtr<IMMDevice> DeviceById(const std::wstring& id) {
  if (id.empty()) return DefaultDevice();
  ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDevice> device;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))))
    enumerator->GetDevice(id.c_str(), &device);
  return device;
}
std::wstring ProcessPath(DWORD pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return L"";
  wchar_t path[32768]; DWORD size = 32768;
  bool ok = QueryFullProcessImageName(process, 0, path, &size) != FALSE;
  CloseHandle(process);
  return ok ? std::wstring(path, size) : L"";
}
std::string DeviceName(IMMDevice* device) {
  ComPtr<IPropertyStore> properties;
  PROPVARIANT name; PropVariantInit(&name);
  if (device && SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) &&
      SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name))) {
    std::string result = name.vt == VT_LPWSTR ? Utf8(name.pwszVal) : "Salida de Windows";
    PropVariantClear(&name); return result;
  }
  return "Salida de Windows";
}
std::string ErrorText(HRESULT hr) {
  std::ostringstream text;
  text << "Windows audio (0x" << std::hex << std::uppercase << static_cast<unsigned long>(hr) << "). ";
  if (hr == AUDCLNT_E_DEVICE_INVALIDATED) text << "Cambió o se desconectó la salida. Vuelve a iniciar el audio.";
  else if (hr == E_ACCESSDENIED) text << "Windows o la app de origen no permiten esta captura.";
  else text << "No se pudo mantener la ruta de audio. Comprueba el dispositivo y vuelve a intentarlo.";
  return text.str();
}

struct Session {
  DWORD pid = 0;
  std::wstring id;
  ComPtr<ISimpleAudioVolume> volume;
  AudioSessionState state = AudioSessionStateInactive;
};
std::vector<Session> Sessions() {
  std::vector<Session> sessions;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDeviceCollection> devices;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      IID_PPV_ARGS(&enumerator))) || FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices))) return sessions;
  UINT device_count = 0; devices->GetCount(&device_count);
  for (UINT d = 0; d < device_count; ++d) {
    ComPtr<IMMDevice> device;
    ComPtr<IAudioSessionManager2> manager;
    ComPtr<IAudioSessionEnumerator> items;
    if (FAILED(devices->Item(d, &device)) || FAILED(device->Activate(__uuidof(IAudioSessionManager2),
        CLSCTX_ALL, nullptr, &manager)) || FAILED(manager->GetSessionEnumerator(&items))) continue;
    int count = 0; items->GetCount(&count);
    for (int i = 0; i < count; ++i) {
      ComPtr<IAudioSessionControl> control;
      ComPtr<IAudioSessionControl2> control2;
      Session item;
      if (FAILED(items->GetSession(i, &control)) || FAILED(control.As(&control2)) ||
          FAILED(control2->GetProcessId(&item.pid)) || !item.pid || item.pid == GetCurrentProcessId() ||
          FAILED(control.As(&item.volume))) continue;
      control->GetState(&item.state);
      LPWSTR id = nullptr;
      if (SUCCEEDED(control2->GetSessionInstanceIdentifier(&id))) { item.id = id; CoTaskMemFree(id); }
      sessions.push_back(std::move(item));
    }
  }
  return sessions;
}

// Only sessions initially unmuted are changed. Restore before releasing the source.
struct SourceMute {
  std::vector<Session> owned;
  HANDLE guard_event = nullptr;
  std::wstring journal;
  bool Guard() {
    wchar_t executable[32768], temp[MAX_PATH];
    GetModuleFileName(nullptr, executable, 32768); GetTempPath(MAX_PATH, temp);
    const auto suffix = std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
    const auto event_name = L"Local\\AudiowavRestore-" + suffix;
    journal = std::wstring(temp) + L"Audiowav-restore-" + suffix + L".txt";
    std::ofstream file(std::filesystem::path(journal), std::ios::binary);
    for (const auto& session : owned) file << session.pid << '\t' << Utf8(session.id) << '\n';
    file.close();
    if (!file) return false;
    guard_event = CreateEvent(nullptr, TRUE, FALSE, event_name.c_str());
    if (!guard_event) return false;
    std::wstring command = L"\"" + std::wstring(executable) + L"\" --audio-guard " +
        std::to_wstring(GetCurrentProcessId()) + L" \"" + event_name + L"\" \"" + journal + L"\"";
    STARTUPINFO startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESHOWWINDOW; startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (!CreateProcess(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) return false;
    CloseHandle(process.hThread); CloseHandle(process.hProcess); return true;
  }
  bool Apply(DWORD pid) {
    for (auto& session : Sessions()) {
      if (session.pid != pid || session.state == AudioSessionStateExpired) continue;
      BOOL muted = TRUE;
      if (FAILED(session.volume->GetMute(&muted)) || muted) continue;
      owned.push_back(std::move(session));
    }
    if (owned.empty() || !Guard()) { Restore(); return false; }
    for (auto& session : owned) {
      BOOL muted = FALSE;
      auto& volume = session.volume;
      if (FAILED(volume->SetMute(TRUE, nullptr)) || FAILED(volume->GetMute(&muted)) || !muted) { Restore(); return false; }
    }
    return !owned.empty();
  }
  bool Confirmed() const {
    if (owned.empty()) return false;
    for (const auto& session : owned) { BOOL value = FALSE;
      if (FAILED(session.volume->GetMute(&value)) || !value) return false;
    }
    return true;
  }
  void Restore() {
    for (auto& session : owned) session.volume->SetMute(FALSE, nullptr);
    owned.clear();
    if (guard_event) { SetEvent(guard_event); CloseHandle(guard_event); guard_event = nullptr; }
    if (!journal.empty()) { DeleteFile(journal.c_str()); journal.clear(); }
  }
  ~SourceMute() { Restore(); }
};

// WRL supplies a free-threaded marshaler for the asynchronous activation callback.
class Activation final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
    IActivateAudioInterfaceCompletionHandler, Microsoft::WRL::FtmBase> {
 public:
  Event done;
  HRESULT status = E_PENDING;
  ComPtr<IAudioClient> client;
  STDMETHODIMP ActivateCompleted(IActivateAudioInterfaceAsyncOperation* operation) override {
    ComPtr<IUnknown> unknown;
    HRESULT result = operation->GetActivateResult(&status, &unknown);
    if (FAILED(result)) status = result;
    if (SUCCEEDED(status)) status = unknown.As(&client);
    SetEvent(done.value); return S_OK;
  }
};
HRESULT ProcessCapture(DWORD pid, ComPtr<IAudioClient>& client, ComPtr<IAudioCaptureClient>& capture, HANDLE event) {
  AUDIOCLIENT_ACTIVATION_PARAMS params{};
  params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  params.ProcessLoopbackParams.TargetProcessId = pid;
  params.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;
  PROPVARIANT variant; PropVariantInit(&variant);
  variant.vt = VT_BLOB; variant.blob.cbSize = sizeof(params);
  variant.blob.pBlobData = reinterpret_cast<BYTE*>(&params);
  auto callback = Microsoft::WRL::Make<Activation>();
  ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
  AW_CHECK(ActivateAudioInterfaceAsync(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
      &variant, callback.Get(), &operation));
  if (WaitForSingleObject(callback->done.value, 10000) != WAIT_OBJECT_0) return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
  AW_CHECK(callback->status);
  client = callback->client;
  WAVEFORMATEX format{WAVE_FORMAT_PCM, 2, rate, rate * 4, 4, 16, 0};
  AW_CHECK(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
      0, 0, &format, nullptr));
  AW_CHECK(client->GetService(IID_PPV_ARGS(&capture)));
  AW_CHECK(client->SetEventHandle(event));
  return client->Start();
}
HRESULT CableCapture(IMMDevice* device, ComPtr<IAudioClient>& client, ComPtr<IAudioCaptureClient>& capture, HANDLE event) {
  if (!device) return AUDCLNT_E_DEVICE_INVALIDATED;
  AW_CHECK(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client));
  WAVEFORMATEX format{WAVE_FORMAT_PCM, 2, rate, rate * 4, 4, 16, 0};
  AW_CHECK(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
      400000, 0, &format, nullptr));
  AW_CHECK(client->GetService(IID_PPV_ARGS(&capture))); AW_CHECK(client->SetEventHandle(event));
  return client->Start();
}
HRESULT Output(IMMDevice* device, ComPtr<IAudioClient>& client, ComPtr<IAudioRenderClient>& render,
    UINT32& frames, HANDLE event) {
  if (!device) return AUDCLNT_E_DEVICE_INVALIDATED;
  AW_CHECK(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client));
  WAVEFORMATEX format{WAVE_FORMAT_IEEE_FLOAT, 2, rate, rate * 8, 8, 32, 0};
  AW_CHECK(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
      AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, 400000, 0, &format, nullptr));
  AW_CHECK(client->GetBufferSize(&frames));
  AW_CHECK(client->GetService(IID_PPV_ARGS(&render)));
  AW_CHECK(client->SetEventHandle(event));
  BYTE* buffer = nullptr;
  AW_CHECK(render->GetBuffer(frames, &buffer));
  AW_CHECK(render->ReleaseBuffer(frames, AUDCLNT_BUFFERFLAGS_SILENT));
  return client->Start();
}
HRESULT OpenReader(const std::wstring& path, ComPtr<IMFSourceReader>& reader, int64_t& duration) {
  AW_CHECK(MFCreateSourceReaderFromURL(path.c_str(), nullptr, &reader));
  AW_CHECK(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
  AW_CHECK(reader->SetStreamSelection(audio_stream, TRUE));
  ComPtr<IMFMediaType> type;
  AW_CHECK(MFCreateMediaType(&type));
  AW_CHECK(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
  AW_CHECK(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float));
  AW_CHECK(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2));
  AW_CHECK(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate));
  AW_CHECK(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 32));
  AW_CHECK(type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 8));
  AW_CHECK(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * 8));
  AW_CHECK(reader->SetCurrentMediaType(audio_stream, nullptr, type.Get()));
  ComPtr<IMFMediaType> actual;
  AW_CHECK(reader->GetCurrentMediaType(audio_stream, &actual));
  UINT32 hz = 0, channels = 0;
  actual->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &hz);
  actual->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
  if (hz != rate || channels != 2) return MF_E_INVALIDMEDIATYPE;
  PROPVARIANT value; PropVariantInit(&value);
  if (SUCCEEDED(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION, &value)) &&
      value.vt == VT_UI8) duration = static_cast<int64_t>(value.uhVal.QuadPart / 10000);
  PropVariantClear(&value); return S_OK;
}
}

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  int count = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), count, nullptr, nullptr);
  return result;
}
std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  int count = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), count);
  return result;
}
WindowsAudio::~WindowsAudio() { Stop(); }
void WindowsAudio::Configure(DesktopSettings settings) {
  bool should_stop = false;
  { std::lock_guard<std::mutex> lock(mutex_); settings_ = settings; ++revision_; should_stop = state_.live && !settings.enabled; }
  if (should_stop) Stop();
}
void WindowsAudio::Open(const std::wstring& path) {
  Stop(); stop_ = false; paused_ = false; seek_ = -1;
  { std::lock_guard<std::mutex> lock(mutex_); state_ = {}; state_.title = Utf8(path.substr(path.find_last_of(L"/\\") + 1)); }
  worker_ = std::thread(&WindowsAudio::Run, this, path, 0, false);
}
void WindowsAudio::StartApp(DWORD pid, std::string label) {
  if (!pid || pid == GetCurrentProcessId()) return;
  Stop(); stop_ = false; paused_ = false; seek_ = -1;
  { std::lock_guard<std::mutex> lock(mutex_); state_ = {}; state_.live = true; state_.pid = pid;
    state_.title = std::move(label); settings_.enabled = true; ++revision_; }
  worker_ = std::thread(&WindowsAudio::Run, this, std::wstring(), pid, false);
}
void WindowsAudio::StartCable(const std::wstring& id, std::string label) {
  Stop(); stop_ = false; paused_ = false; seek_ = -1;
  { std::lock_guard<std::mutex> lock(mutex_); state_ = {}; state_.live = true;
    state_.title = std::move(label); settings_.enabled = true; ++revision_; }
  worker_ = std::thread(&WindowsAudio::Run, this, id, 0, true);
}
void WindowsAudio::SelectOutput(const std::wstring& id) {
  Stop(); std::lock_guard<std::mutex> lock(mutex_); output_id_ = id;
}
void WindowsAudio::Stop() {
  stop_ = true;
  if (worker_.joinable()) worker_.join();
  std::lock_guard<std::mutex> lock(mutex_);
  state_.running = state_.ready = state_.playing = state_.live = state_.muted = state_.tail = state_.has_file = false;
}
void WindowsAudio::Toggle() {
  const auto state = Snapshot();
  if (paused_ && state.duration > 0 && state.position >= state.duration) seek_ = 0;
  paused_ = !paused_.load();
}
void WindowsAudio::Seek(int64_t milliseconds) { seek_ = std::max<int64_t>(0, milliseconds); }
DesktopState WindowsAudio::Snapshot() { std::lock_guard<std::mutex> lock(mutex_); return state_; }
std::vector<AudioApp> WindowsAudio::Apps() {
  std::vector<AudioApp> apps;
  for (const auto& session : Sessions()) {
    if (session.state != AudioSessionStateActive) continue;
    if (std::any_of(apps.begin(), apps.end(), [&](const AudioApp& item) { return item.pid == session.pid; })) continue;
    std::wstring path = ProcessPath(session.pid);
    if (path.empty()) continue;
    apps.push_back({session.pid, Utf8(path.substr(path.find_last_of(L"/\\") + 1))});
  }
  return apps;
}
std::vector<AudioDevice> WindowsAudio::Devices() {
  std::vector<AudioDevice> result;
  ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDeviceCollection> devices;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) ||
      FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices))) return result;
  UINT count = 0; devices->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    ComPtr<IMMDevice> device; LPWSTR id = nullptr;
    if (FAILED(devices->Item(i, &device)) || FAILED(device->GetId(&id))) continue;
    std::string name = DeviceName(device.Get()), lower = name;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    const bool cable = lower.find("cable input") != std::string::npos || lower.find("vb-audio") != std::string::npos ||
        lower.find("virtual cable") != std::string::npos || lower.find("voicemeeter input") != std::string::npos;
    result.push_back({id, name, cable}); CoTaskMemFree(id);
  }
  return result;
}
float WindowsAudio::Volume() {
  auto device = DefaultDevice(); ComPtr<IAudioEndpointVolume> volume;
  float value = .5f;
  if (device && SUCCEEDED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, &volume)))
    volume->GetMasterVolumeLevelScalar(&value);
  return value;
}
void WindowsAudio::Volume(float level) {
  auto device = DefaultDevice(); ComPtr<IAudioEndpointVolume> volume;
  if (device && SUCCEEDED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, &volume)))
    volume->SetMasterVolumeLevelScalar(std::clamp(level, 0.f, 1.f), nullptr);
}

void WindowsAudio::Run(std::wstring path, DWORD pid, bool cable) {
  ComScope com;
  HRESULT hr = com.hr;
  const bool mf_started = SUCCEEDED(hr) && SUCCEEDED(hr = MFStartup(MF_VERSION, MFSTARTUP_LITE));
  SourceMute mute;
  DesktopState state;
  std::wstring output_id;
  { std::lock_guard<std::mutex> lock(mutex_); state = state_; output_id = output_id_; }
  const bool live = pid != 0 || cable;
  auto device = DeviceById(output_id); state.device = DeviceName(device.Get());
  ComPtr<IAudioClient> output, input;
  ComPtr<IAudioRenderClient> render;
  ComPtr<IAudioCaptureClient> capture;
  ComPtr<IMFSourceReader> reader;
  Event output_event, capture_event;
  DWORD task_index = 0;
  HANDLE task = AvSetMmThreadCharacteristics(L"Pro Audio", &task_index);
  DesktopDsp dsp;
  auto execute = [&]() -> HRESULT {
    if (FAILED(hr)) return hr;
    UINT32 capacity = 0;
    if (pid) AW_CHECK(ProcessCapture(pid, input, capture, capture_event.value));
    else if (cable) {
      LPWSTR destination = nullptr;
      if (!device || FAILED(device->GetId(&destination))) return AUDCLNT_E_DEVICE_INVALIDATED;
      const bool feedback = path == destination; CoTaskMemFree(destination);
      if (feedback) { state.error = "Elige unos altavoces o auriculares como salida; no puede ser el mismo cable virtual de entrada."; return E_INVALIDARG; }
      auto source = DeviceById(path); AW_CHECK(CableCapture(source.Get(), input, capture, capture_event.value));
      state.muted = true; // The virtual endpoint isolates dry audio from the physical return.
    }
    else AW_CHECK(OpenReader(path, reader, state.duration));
    AW_CHECK(Output(device.Get(), output, render, capacity, output_event.value));
    state.running = true; state.has_file = !live; state.ready = !live;
    std::vector<float> decoded;
    size_t cursor = 0;
    std::array<float, rate * 2> ring{};
    size_t read = 0, write = 0, queued = 0;
    std::array<float, block_frames * 2> block{};
    DesktopSettings settings;
    uint64_t applied = UINT64_MAX;
    bool eof = false, fallback = false, signal_seen = false, output_started = true, muted_signal = false;
    int64_t source_frames = 0, tail_frames = 0;
    auto started = Clock::now(), last_signal = started, last_publish = started;
    auto muted_at = started, last_control = started;
    while (!stop_) {
      const auto now = Clock::now();
      bool changed = false;
      { std::lock_guard<std::mutex> lock(mutex_);
        if (applied != revision_) { settings = settings_; applied = revision_; changed = true; }
      }
      if (changed) dsp.Configure(settings, live && !state.muted);
      if (live) {
        UINT32 packet = 0;
        AW_CHECK(capture->GetNextPacketSize(&packet));
        while (packet && !stop_) {
          BYTE* data = nullptr; UINT32 count = 0; DWORD flags = 0;
          AW_CHECK(capture->GetBuffer(&data, &count, &flags, nullptr, nullptr));
          if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) ++state.discontinuities;
          const auto* pcm = reinterpret_cast<const int16_t*>(data);
          float peak = 0;
          for (UINT32 i = 0; i < count * 2; ++i) {
            float value = (flags & AUDCLNT_BUFFERFLAGS_SILENT) ? 0 : pcm[i] / 32768.f;
            peak = std::max(peak, std::abs(value));
            if (queued == ring.size()) { read = (read + 2) % ring.size(); queued -= 2; ++state.discontinuities; }
            ring[write] = value; write = (write + 1) % ring.size(); ++queued;
          }
          AW_CHECK(capture->ReleaseBuffer(count));
          state.peak = peak;
          if (peak > .0001f) {
            last_signal = now; signal_seen = true;
            if (state.muted && now - muted_at > std::chrono::milliseconds(200)) muted_signal = true;
          }
          AW_CHECK(capture->GetNextPacketSize(&packet));
        }
        state.signal = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_signal).count() < 1500 && signal_seen;
        state.ready = signal_seen;
        if (!signal_seen && now - started > std::chrono::seconds(12)) return HRESULT_FROM_WIN32(ERROR_NO_DATA);
        if (pid && signal_seen && !state.muted && !fallback) {
          state.muted = mute.Apply(pid); muted_at = now;
          if (!state.muted) { fallback = true; state.mute_error = "No se pudo controlar el original. Se usa solo retorno WET."; }
          dsp.Configure(settings, !state.muted);
        }
        const bool check_control = now - last_control > std::chrono::milliseconds(500);
        if (check_control) last_control = now;
        if (pid && state.muted && ((check_control && !mute.Confirmed()) ||
            (!muted_signal && now - muted_at > std::chrono::seconds(2) && !state.signal))) {
          mute.Restore(); state.muted = false; fallback = true;
          state.mute_error = "Se liberó el original al perder control o señal. Retorno WET activo.";
          dsp.Configure(settings, true);
        }
        // Bound excess latency after scheduling stalls or input/output clock drift.
        if (queued > rate / 5 * 2) { const size_t excess = queued - rate / 20 * 2;
          read = (read + excess) % ring.size(); queued -= excess; ++state.discontinuities; dsp.Reset(); }
      }
      const int64_t requested = seek_.exchange(-1);
      if (!live && requested >= 0) {
        const int64_t position = state.duration > 0 ? std::min(requested, state.duration) : requested;
        PROPVARIANT value; PropVariantInit(&value); value.vt = VT_I8; value.hVal.QuadPart = position * 10000;
        AW_CHECK(reader->SetCurrentPosition(GUID_NULL, value));
        AW_CHECK(output->Stop()); output_started = false; AW_CHECK(output->Reset());
        dsp.Reset(); decoded.clear(); cursor = 0; eof = false; tail_frames = 0;
        source_frames = position * rate / 1000; state.position = position;
      }
      state.playing = !paused_;
      if (!live && paused_) {
        if (output_started) { AW_CHECK(output->Stop()); output_started = false; }
        if (now - last_publish > std::chrono::milliseconds(100)) {
          std::lock_guard<std::mutex> lock(mutex_); state_ = state; last_publish = now;
        }
        Sleep(10); continue;
      }
      if (!output_started) { AW_CHECK(output->Start()); output_started = true; }
      UINT32 padding = 0;
      AW_CHECK(output->GetCurrentPadding(&padding));
      UINT32 available = capacity - padding;
      if (padding == 0 && state.frames > rate / 10) ++state.underruns;
      while (available && !stop_) {
        const UINT32 count = std::min<UINT32>(available, block_frames);
        std::fill(block.begin(), block.end(), 0.f);
        if (live) {
          const size_t samples = std::min<size_t>(queued, count * 2);
          for (size_t i = 0; i < samples; ++i) { block[i] = ring[read]; read = (read + 1) % ring.size(); }
          queued -= samples;
        } else {
          UINT32 filled = 0;
          while (filled < count && !eof) {
            if (cursor >= decoded.size()) {
              ComPtr<IMFSample> sample;
              DWORD flags = 0;
              AW_CHECK(reader->ReadSample(audio_stream, 0, nullptr, &flags, nullptr, &sample));
              if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) return MF_E_INVALIDMEDIATYPE;
              if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { eof = true; break; }
              if (!sample) continue;
              ComPtr<IMFMediaBuffer> buffer;
              AW_CHECK(sample->ConvertToContiguousBuffer(&buffer));
              BYTE* bytes = nullptr; DWORD length = 0;
              AW_CHECK(buffer->Lock(&bytes, nullptr, &length));
              if (length % 8 || length > 16 * 1024 * 1024) { buffer->Unlock(); return MF_E_INVALIDMEDIATYPE; }
              const auto* floats = reinterpret_cast<const float*>(bytes);
              decoded.assign(floats, floats + length / sizeof(float)); cursor = 0;
              AW_CHECK(buffer->Unlock());
            }
            const size_t samples = std::min<size_t>((count - filled) * 2, decoded.size() - cursor);
            std::copy_n(decoded.data() + cursor, samples, block.data() + filled * 2);
            cursor += samples; filled += static_cast<UINT32>(samples / 2); source_frames += samples / 2;
          }
          if (eof) tail_frames += count - filled;
          state.tail = eof;
          state.position = state.duration > 0 ? std::min(state.duration, source_frames * 1000 / rate) : source_frames * 1000 / rate;
        }
        auto before = Clock::now();
        dsp.Process(block.data(), static_cast<int>(count));
        state.max_micros = std::max<int64_t>(state.max_micros, std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - before).count());
        state.frames += count; state.limited = static_cast<int64_t>(dsp.limited_samples());
        BYTE* output_data = nullptr;
        AW_CHECK(render->GetBuffer(count, &output_data));
        memcpy(output_data, block.data(), count * 8);
        AW_CHECK(render->ReleaseBuffer(count, 0));
        available -= count;
        const double tail_seconds = settings.enabled && settings.reverb.enabled ? std::min(22.0, settings.reverb.decay + 1.0) : .05;
        if (!live && eof && tail_frames > tail_seconds * rate) {
          // Drain the final queued samples before pausing at end of file.
          while (!stop_) { UINT32 pending = 0; AW_CHECK(output->GetCurrentPadding(&pending)); if (!pending) break; Sleep(5); }
          paused_ = true; state.playing = false; state.tail = false; break;
        }
      }
      if (now - last_publish >= std::chrono::milliseconds(100)) {
        std::lock_guard<std::mutex> lock(mutex_); state_ = state; last_publish = now;
      }
      WaitForSingleObject(output_event.value, 5);
    }
    return S_OK;
  };
  hr = execute();
  mute.Restore();
  if (input) input->Stop();
  if (output) output->Stop();
  capture.Reset(); render.Reset(); input.Reset(); output.Reset(); reader.Reset();
  if (task) AvRevertMmThreadCharacteristics(task);
  if (mf_started) MFShutdown();
  state.running = state.ready = state.playing = state.muted = false;
  if (FAILED(hr) && !stop_ && state.error.empty()) state.error = ErrorText(hr);
  std::lock_guard<std::mutex> lock(mutex_); state_ = state;
}

int WindowsAudio::RestoreGuard(DWORD parent, const std::wstring& event, const std::wstring& journal) {
  HANDLE parent_process = OpenProcess(SYNCHRONIZE, FALSE, parent);
  HANDLE finished = OpenEvent(SYNCHRONIZE, FALSE, event.c_str());
  if (parent_process && finished) {
    HANDLE waits[]{finished, parent_process};
    DWORD result = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
    if (result == WAIT_OBJECT_0) { CloseHandle(parent_process); CloseHandle(finished); return 0; }
  }
  if (parent_process) CloseHandle(parent_process);
  if (finished) CloseHandle(finished);
  ComScope com;
  std::ifstream file{std::filesystem::path(journal)};
  std::vector<std::pair<DWORD, std::wstring>> originals;
  std::string line;
  while (std::getline(file, line)) {
    const auto split = line.find('\t');
    if (split == std::string::npos) continue;
    DWORD pid = static_cast<DWORD>(strtoul(line.substr(0, split).c_str(), nullptr, 10));
    if (pid) originals.emplace_back(pid, Wide(line.substr(split + 1)));
  }
  for (auto& session : Sessions()) for (const auto& original : originals)
    if (session.pid == original.first && session.id == original.second) session.volume->SetMute(FALSE, nullptr);
  file.close(); DeleteFile(journal.c_str()); return 0;
}
}
