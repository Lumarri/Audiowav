#pragma once
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/binary_messenger.h>
#include "windows_audio.h"

class DesktopAudioPlugin {
 public:
  DesktopAudioPlugin(flutter::BinaryMessenger* messenger, HWND window);
 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::EncodableValue Snapshot();
  void Configure();
  void Save();
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  flutter::EncodableMap settings_;
  std::vector<audiowav::AudioApp> apps_;
  std::vector<audiowav::AudioDevice> devices_;
  std::string output_id_;
  ULONGLONG scanned_ = 0;
  audiowav::WindowsAudio audio_;
};
