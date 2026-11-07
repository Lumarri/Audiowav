#include "audio_dsp.h"
#include <algorithm>
#include <cmath>

namespace audiowav {
namespace { constexpr double pi = 3.14159265358979323846; }
DesktopDsp::DesktopDsp(int rate) : rate_(rate), reverb_(rate) {}
float DesktopDsp::Filter::Tick(float input, int channel) {
  const double out = b0 * input + z1[channel];
  z1[channel] = b1 * input - a1 * out + z2[channel];
  z2[channel] = b2 * input - a2 * out;
  return static_cast<float>(out);
}
void DesktopDsp::Configure(const DesktopSettings& settings, bool wetOnly) {
  enabled_ = settings.enabled;
  const double frequencies[] = {60, 230, 910, 3600, 14000, 100};
  for (int i = 0; i < 6; ++i) {
    auto& f = filters_[i];
    const double db = i < 5 ? settings.bands[i] : settings.bass * 12;
    const double a = std::pow(10.0, db / 40);
    const double w = 2 * pi * std::min(frequencies[i], rate_ * .45) / rate_;
    const double c = std::cos(w), s = std::sin(w);
    double b0, b1, b2, a0, a1, a2;
    if (i < 5) {
      const double alpha = s / (2 * .8);
      b0 = 1 + alpha * a; b1 = -2 * c; b2 = 1 - alpha * a;
      a0 = 1 + alpha / a; a1 = -2 * c; a2 = 1 - alpha / a;
    } else {
      const double t = 2 * std::sqrt(a) * s / std::sqrt(2.0);
      b0 = a * ((a + 1) - (a - 1) * c + t);
      b1 = 2 * a * ((a - 1) - (a + 1) * c);
      b2 = a * ((a + 1) - (a - 1) * c - t);
      a0 = (a + 1) + (a - 1) * c + t;
      a1 = -2 * ((a - 1) + (a + 1) * c);
      a2 = (a + 1) + (a - 1) * c - t;
    }
    f.b0 = b0 / a0; f.b1 = b1 / a0; f.b2 = b2 / a0;
    f.a1 = a1 / a0; f.a2 = a2 / a0;
  }
  auto p = settings.reverb;
  p.enabled = settings.enabled && p.enabled;
  if (wetOnly) {
    if (!p.enabled) p.wet = 0;
    p.enabled = true;
    p.dry = 0;
  }
  reverb_.configure(p);
  target_gain_ = static_cast<float>(std::pow(10.0, settings.enabled ? settings.gain / 20 : 0));
  target_left_ = static_cast<float>(1 - std::max(0.0, settings.enabled ? settings.balance : 0));
  target_right_ = static_cast<float>(1 + std::min(0.0, settings.enabled ? settings.balance : 0));
}
void DesktopDsp::Reset() {
  reverb_.reset();
  for (auto& f : filters_) { f.z1.fill(0); f.z2.fill(0); }
  limiter_ = 1;
}
void DesktopDsp::Process(float* stereo, int frames) {
  for (int i = 0; i < frames * 2; ++i)
    stereo[i] = std::isfinite(stereo[i]) ? std::clamp(stereo[i], -8.f, 8.f) : 0.f;
  if (enabled_) for (int i = 0; i < frames * 2; ++i)
    for (auto& f : filters_) stereo[i] = f.Tick(stereo[i], i % 2);
  reverb_.process(stereo, frames);
  const float smoothing = 1 - std::exp(-1.f / (.02f * rate_));
  for (int i = 0; i < frames; ++i) {
    gain_ += (target_gain_ - gain_) * smoothing;
    left_ += (target_left_ - left_) * smoothing;
    right_ += (target_right_ - right_) * smoothing;
    float l = stereo[i * 2] * gain_ * left_, r = stereo[i * 2 + 1] * gain_ * right_;
    if (!std::isfinite(l)) l = 0;
    if (!std::isfinite(r)) r = 0;
    const float peak = std::max(std::abs(l), std::abs(r));
    const float wanted = peak > .98f ? .98f / peak : 1;
    if (wanted < limiter_) { limiter_ = wanted; ++limited_; }
    else limiter_ += (1 - limiter_) * (1 - std::exp(-1.f / (.05f * rate_)));
    stereo[i * 2] = std::clamp(l * limiter_, -1.f, 1.f);
    stereo[i * 2 + 1] = std::clamp(r * limiter_, -1.f, 1.f);
  }
}
}
