#include "audio_dsp.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>

namespace {
constexpr double pi = 3.14159265358979323846;
double response(audiowav::DesktopSettings settings, double frequency) {
  audiowav::DesktopDsp dsp;
  dsp.Configure(settings);
  std::array<float, 960> block{};
  double energy = 0; int samples = 0;
  for (int n = 0; n < 150; ++n) {
    for (int i = 0; i < 480; ++i) block[i * 2] = block[i * 2 + 1] =
        static_cast<float>(.01 * std::sin((n * 480 + i) * 2 * pi * frequency / 48000));
    dsp.Process(block.data(), 480);
    if (n > 100) for (float value : block) { energy += value * value; ++samples; }
  }
  return std::sqrt(energy / samples);
}
}
int main() {
  int failures = 0;
  auto check = [&](bool ok, const char* name) { std::cout << (ok ? "PASS " : "FAIL ") << name << '\n'; if (!ok) ++failures; };
  audiowav::DesktopSettings settings; settings.enabled = true;
  const double flat = response(settings, 910);
  settings.bands[2] = 6;
  check(std::abs(20 * std::log10(response(settings, 910) / flat) - 6) < .2, "Peaking EQ provides +6 dB at its center");
  settings = {}; settings.enabled = true; settings.bass = 1;
  audiowav::DesktopSettings base; base.enabled = true;
  const double bass = response(settings, 30) / response(base, 30);
  check(bass > 3.5 && bass < 4.1, "Bass shelf boosts low frequencies by about 12 dB");
  check(std::abs(response(settings, 4000) / response(base, 4000) - 1) < .02, "Bass shelf preserves high frequencies");
  settings = base; settings.gain = 6;
  check(std::abs(20 * std::log10(response(settings, 910) / flat) - 6) < .1, "Gain adds the selected decibels");
  settings.enabled = false; settings.bands.fill(12); settings.bass = 1;
  check(std::abs(response(settings, 910) / flat - 1) < .001, "Master bypass removes EQ, bass and gain");
  audiowav::DesktopDsp limiter; settings = base; settings.gain = 12; settings.bands.fill(12);
  limiter.Configure(settings); std::array<float, 960> block; block.fill(.9f);
  bool bounded = true;
  for (int n = 0; n < 30; ++n) {
    block.fill(.9f); limiter.Process(block.data(), 480);
    for (float value : block) bounded &= std::isfinite(value) && std::abs(value) <= 1;
  }
  check(bounded && limiter.limited_samples() > 0, "Limiter bounds boosted samples and reports peaks");
  audiowav::DesktopDsp wet;
  settings = {}; wet.Configure(settings, true); block.fill(.2f); wet.Process(block.data(), 480);
  check(std::all_of(block.begin(), block.end(), [](float value) { return value == 0; }), "WET-only fallback never duplicates dry audio, including bypass");
  settings = base; settings.balance = -1;
  audiowav::DesktopDsp balance; balance.Configure(settings);
  for (int n = 0; n < 100; ++n) { block.fill(.01f); balance.Process(block.data(), 480); }
  check(std::abs(block[1]) < .00001f && std::abs(block[0] - .01f) < .00001f, "Balance can isolate the left channel");
  return failures ? 1 : 0;
}
