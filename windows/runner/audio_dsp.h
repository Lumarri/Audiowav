#pragma once
#include <array>
#include <cstdint>
#include "reverb.h"

namespace audiowav {
struct DesktopSettings {
  bool enabled = false;
  std::array<double, 5> bands{};
  double bass = 0, gain = 0, balance = 0;
  Parameters reverb;
};

// Owned exclusively by the WASAPI worker; configure only at block boundaries.
class DesktopDsp {
 public:
  explicit DesktopDsp(int rate = 48000);
  void Configure(const DesktopSettings& settings, bool wetOnly = false);
  void Reset();
  void Process(float* stereo, int frames);
  uint64_t limited_samples() const { return limited_; }
 private:
  struct Filter {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    std::array<double, 2> z1{}, z2{};
    float Tick(float input, int channel);
  };
  int rate_;
  Reverb reverb_;
  std::array<Filter, 6> filters_;
  bool enabled_ = false;
  float gain_ = 1, target_gain_ = 1, left_ = 1, right_ = 1;
  float target_left_ = 1, target_right_ = 1, limiter_ = 1;
  uint64_t limited_ = 0;
};
}
