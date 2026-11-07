#include "desktop_audio_plugin.h"
#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl.h>
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>

using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using Microsoft::WRL::ComPtr;
namespace {
const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto item = map.find(EncodableValue(key)); return item == map.end() ? nullptr : &item->second;
}
double Number(const EncodableValue* value, double fallback = 0) {
  if (!value) return fallback;
  if (const auto* d = std::get_if<double>(value)) return std::isfinite(*d) ? *d : fallback;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* i = std::get_if<int64_t>(value)) return static_cast<double>(*i);
  return fallback;
}
double Number(const EncodableMap& map, const char* key, double fallback, double min, double max) {
  return std::clamp(Number(Find(map, key), fallback), min, max);
}
bool Boolean(const EncodableMap& map, const char* key) {
  const auto* item = Find(map, key); return item && std::get_if<bool>(item) && std::get<bool>(*item);
}
EncodableMap Capabilities(bool available) {
  return {{EncodableValue("equalizer"), EncodableValue(available)}, {EncodableValue("bass"), EncodableValue(available)},
      {EncodableValue("gain"), EncodableValue(available)}, {EncodableValue("reverb"), EncodableValue(available)}};
}
std::filesystem::path SettingsPath() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder))) return {};
  std::filesystem::path directory = std::filesystem::path(folder) / L"Audiowav";
  CoTaskMemFree(folder);
  std::error_code error; std::filesystem::create_directories(directory, error);
  return directory / L"settings.bin";
}
}
DesktopAudioPlugin::DesktopAudioPlugin(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  const auto path = SettingsPath();
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (file && file.tellg() > 0 && file.tellg() < 1024 * 1024) {
    std::vector<uint8_t> bytes(static_cast<size_t>(file.tellg())); file.seekg(0);
    file.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    auto value = flutter::StandardMessageCodec::GetInstance().DecodeMessage(bytes);
    if (value && std::get_if<EncodableMap>(value.get())) settings_ = std::get<EncodableMap>(*value);
  }
  settings_[EncodableValue("enabled")] = EncodableValue(false);
  Configure();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "audiowav/audio",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { Handle(call, std::move(result)); });
}
void DesktopAudioPlugin::Save() {
  auto bytes = flutter::StandardMessageCodec::GetInstance().EncodeMessage(EncodableValue(settings_));
  auto path = SettingsPath(); if (path.empty()) return;
  auto temporary = path; temporary += L".tmp";
  std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
  if (!file || !bytes) return;
  file.write(reinterpret_cast<const char*>(bytes->data()), static_cast<std::streamsize>(bytes->size())); file.close();
  if (file) MoveFileEx(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}
void DesktopAudioPlugin::Configure() {
  audiowav::DesktopSettings s;
  s.enabled = Boolean(settings_, "enabled");
  s.bass = Number(settings_, "bass", 0, 0, 1); s.gain = Number(settings_, "gain", 0, 0, 12);
  s.balance = Number(settings_, "balance", 0, -1, 1);
  if (const auto* bands = Find(settings_, "bands")) if (const auto* list = std::get_if<EncodableList>(bands))
    for (size_t i = 0; i < std::min<size_t>(5, list->size()); ++i) s.bands[i] = std::clamp(Number(&(*list)[i]), -12.0, 12.0);
  EncodableMap p;
  if (const auto* item = Find(settings_, "reverbParams")) if (const auto* map = std::get_if<EncodableMap>(item)) p = *map;
  s.reverb.enabled = Number(Find(settings_, "reverb")) != 0;
  s.reverb.decay = static_cast<float>(Number(p, "decay", 1.4, .1, 20));
  s.reverb.predelay = static_cast<float>(Number(p, "preDelay", 10, 0, 100));
  s.reverb.size = static_cast<float>(Number(p, "size", 85, 0, 100));
  s.reverb.diffusion = static_cast<float>(Number(p, "diffusion", 100, 0, 100));
  s.reverb.hfRatio = static_cast<float>(Number(p, "hfRatio", .8, .1, 2));
  s.reverb.hfLevel = static_cast<float>(Number(p, "hfLevel", -6, -90, 0));
  s.reverb.earlyLevel = static_cast<float>(Number(p, "earlyLevel", .25, 0, 1));
  s.reverb.earlyDelay = static_cast<float>(Number(p, "earlyDelay", 7, 0, 300));
  s.reverb.dry = static_cast<float>(Number(p, "dry", 1, 0, 1));
  s.reverb.wet = static_cast<float>(Number(settings_, "wet", .25, 0, 1));
  s.reverb.lowCut = static_cast<float>(Number(p, "lowCut", 20, 20, 2000));
  s.reverb.highCut = static_cast<float>(Number(p, "highCut", 18000, 2000, 20000));
  s.reverb.width = static_cast<float>(Number(p, "width", 1, 0, 2));
  audio_.Configure(s);
}
EncodableValue DesktopAudioPlugin::Snapshot() {
  if (GetTickCount64() - scanned_ > 2000) { apps_ = audiowav::WindowsAudio::Apps();
    devices_ = audiowav::WindowsAudio::Devices(); scanned_ = GetTickCount64(); }
  const auto s = audio_.Snapshot();
  EncodableList targets;
  for (const auto& app : apps_) targets.emplace_back(EncodableMap{
      {EncodableValue("id"), EncodableValue(std::to_string(app.pid))},
      {EncodableValue("label"), EncodableValue(app.name + " · PID " + std::to_string(app.pid))}});
  EncodableList outputs;
  outputs.emplace_back(EncodableMap{{EncodableValue("id"), EncodableValue("")},
      {EncodableValue("label"), EncodableValue("Predeterminada de Windows")}});
  for (const auto& device : devices_) {
    outputs.emplace_back(EncodableMap{{EncodableValue("id"), EncodableValue(audiowav::Utf8(device.id))},
        {EncodableValue("label"), EncodableValue(device.name)}});
    if (device.virtual_cable) targets.emplace_back(EncodableMap{
        {EncodableValue("id"), EncodableValue("cable:" + audiowav::Utf8(device.id))},
        {EncodableValue("label"), EncodableValue("Cable virtual · " + device.name)}});
  }
  EncodableMap capture{
      {EncodableValue("mode"), EncodableValue("dsp")},
      {EncodableValue("active"), EncodableValue(s.live && s.error.empty())},
      {EncodableValue("status"), EncodableValue(!s.error.empty() ? "error" : s.live ? "running" : "idle")},
      {EncodableValue("dspReady"), EncodableValue(s.live && s.ready)},
      {EncodableValue("originalMuted"), EncodableValue(s.muted)},
      {EncodableValue("signalDetected"), EncodableValue(s.signal)},
      {EncodableValue("target"), EncodableValue(std::to_string(s.pid))},
      {EncodableValue("label"), EncodableValue(s.title)},
      {EncodableValue("outputCapabilities"), EncodableValue(Capabilities(true))},
      {EncodableValue("processedFrames"), EncodableValue(s.frames)},
      {EncodableValue("error"), s.error.empty() ? EncodableValue() : EncodableValue(s.error)},
      {EncodableValue("muteError"), s.mute_error.empty() ? EncodableValue() : EncodableValue(s.mute_error)}};
  return EncodableValue(EncodableMap{
      {EncodableValue("platform"), EncodableValue("windows")},
      {EncodableValue("running"), EncodableValue(s.running)},
      {EncodableValue("settings"), EncodableValue(settings_)},
      {EncodableValue("hasTrack"), EncodableValue(s.has_file)},
      {EncodableValue("playing"), EncodableValue(s.playing)},
      {EncodableValue("localDsp"), EncodableValue(s.has_file && s.ready)},
      {EncodableValue("localSampleRate"), EncodableValue(48000)},
      {EncodableValue("duration"), EncodableValue(s.duration)},
      {EncodableValue("position"), EncodableValue(s.position)},
      {EncodableValue("title"), EncodableValue(s.has_file ? s.title : "Tu próxima canción")},
      {EncodableValue("tail"), EncodableValue(s.tail)},
      {EncodableValue("sessions"), EncodableValue(s.live && s.ready ? 1 : 0)},
      {EncodableValue("externalPlayingSessions"), EncodableValue(s.live && s.running ? 1 : 0)},
      {EncodableValue("capabilities"), EncodableValue(Capabilities(s.ready))},
      {EncodableValue("externalCapabilities"), EncodableValue(Capabilities(s.live && s.ready))},
      {EncodableValue("captureSupported"), EncodableValue(true)},
      {EncodableValue("captureTargets"), EncodableValue(targets)},
      {EncodableValue("captureProbe"), EncodableValue(capture)},
      {EncodableValue("advancedDetection"), EncodableValue(true)},
      {EncodableValue("volume"), EncodableValue(static_cast<double>(audiowav::WindowsAudio::Volume()))},
      {EncodableValue("error"), s.error.empty() ? EncodableValue() : EncodableValue(s.error)},
      {EncodableValue("outputDevice"), EncodableValue(s.device)},
      {EncodableValue("outputDevices"), EncodableValue(outputs)},
      {EncodableValue("selectedOutput"), EncodableValue(output_id_)},
      {EncodableValue("processedFrames"), EncodableValue(s.frames)},
      {EncodableValue("maxProcessMicros"), EncodableValue(s.max_micros)},
      {EncodableValue("underruns"), EncodableValue(s.underruns)},
      {EncodableValue("discontinuities"), EncodableValue(s.discontinuities)},
      {EncodableValue("limitedSamples"), EncodableValue(s.limited)}});
}
void DesktopAudioPlugin::Handle(const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "initialize" || method == "snapshot") { result->Success(Snapshot()); return; }
  if (method == "configure") {
    if (call.arguments() && std::get_if<EncodableMap>(call.arguments())) {
      settings_ = std::get<EncodableMap>(*call.arguments()); Configure(); Save();
    }
  } else if (method == "openFile") {
    ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (SUCCEEDED(hr)) {
      COMDLG_FILTERSPEC types[]{{L"Audio (WAV, MP3, M4A, AAC, FLAC, WMA)", L"*.wav;*.mp3;*.m4a;*.aac;*.flac;*.wma"}, {L"Todos los archivos", L"*.*"}};
      dialog->SetFileTypes(2, types); dialog->SetOptions(FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM);
      hr = dialog->Show(window_);
      if (SUCCEEDED(hr)) {
        ComPtr<IShellItem> item; PWSTR path = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item)) && SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
          audio_.Open(path); CoTaskMemFree(path); result->Success(EncodableValue(true)); return;
        }
      }
    }
    if (FAILED(hr) && hr != HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Error("FILE_ERROR", "No se pudo abrir el selector de archivos."); return; }
    result->Success(EncodableValue(false)); return;
  } else if (method == "startExternalDsp") {
    const auto* id = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (id && id->rfind("cable:", 0) == 0) {
      const auto device = std::find_if(devices_.begin(), devices_.end(), [&](const auto& item) {
        return item.virtual_cable && "cable:" + audiowav::Utf8(item.id) == *id;
      });
      if (device == devices_.end()) { result->Error("DEVICE_GONE", "No se encontró el cable virtual."); return; }
      settings_[EncodableValue("enabled")] = EncodableValue(true); Configure(); Save();
      audio_.StartCable(device->id, "Cable virtual · " + device->name); result->Success(); return;
    }
    auto app = apps_.end();
    if (id) app = std::find_if(apps_.begin(), apps_.end(), [&](const auto& item) { return std::to_string(item.pid) == *id; });
    if (app == apps_.end()) { result->Error("APP_GONE", "Inicia audio en la app y vuelve a elegirla."); return; }
    settings_[EncodableValue("enabled")] = EncodableValue(true); Configure(); Save(); audio_.StartApp(app->pid, app->name);
  } else if (method == "stopCaptureProbe" || method == "stop") { audio_.Stop();
    if (method == "stop") { settings_[EncodableValue("enabled")] = EncodableValue(false); Configure(); Save(); }
  } else if (method == "selectOutput") {
    const auto* id = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!id || (!id->empty() && std::none_of(devices_.begin(), devices_.end(), [&](const auto& item) { return audiowav::Utf8(item.id) == *id; }))) {
      result->Error("DEVICE_GONE", "La salida elegida ya no está disponible."); return;
    }
    output_id_ = *id; audio_.SelectOutput(audiowav::Wide(*id));
  } else if (method == "togglePlayback") audio_.Toggle();
  else if (method == "seek") audio_.Seek(static_cast<int64_t>(Number(call.arguments())));
  else if (method == "volume") audiowav::WindowsAudio::Volume(static_cast<float>(Number(call.arguments(), .5)));
  else { result->NotImplemented(); return; }
  result->Success();
}
