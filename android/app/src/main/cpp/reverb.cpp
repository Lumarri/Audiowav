#include "reverb.h"
#include <algorithm>
#include <cmath>

namespace audiowav {
namespace {
float bounded(float v, float lo, float hi, float fallback) {
    return std::isfinite(v) ? std::clamp(v, lo, hi) : fallback;
}
float clean(float v) { return std::abs(v) < 1e-20f ? 0.f : v; }
float interpolate(float a, float b, float t) { return a + (b - a) * t; }
constexpr float baseLengths[] = {1493, 1601, 1747, 1867, 1999, 2137, 2371, 2539};
constexpr float diffusionLengths[] = {113, 337, 521, 733};
}

float Reverb::Delay::read(float delay) const {
    // position points at the next write; fractional reads make size changes continuous.
    const float d = std::clamp(delay, 1.f, float(samples.size() - 2));
    const int whole = int(d);
    int a = position - whole;
    if (a < 0) a += int(samples.size());
    int b = a - 1;
    if (b < 0) b += int(samples.size());
    return interpolate(samples[a], samples[b], d - whole);
}
void Reverb::Delay::push(float v) {
    samples[position] = clean(v);
    if (++position == int(samples.size())) position = 0;
}
void Reverb::Delay::clear() { std::fill(samples.begin(), samples.end(), 0); position = 0; }

Reverb::Reverb(int sampleRate) : rate(std::clamp(sampleRate, 8000, 192000)) {
    for (auto& line : lines) line = Delay(int(rate * .12f) + 8);
    for (auto& line : allpasses) line = Delay(int(rate * .02f) + 8);
    for (auto& line : input) line = Delay(int(rate * .5f) + 8);
}
void Reverb::configure(Parameters p) {
    p.decay = bounded(p.decay, .1f, 20, 1.4f);
    p.predelay = bounded(p.predelay, 0, 100, 10);
    p.size = bounded(p.size, 0, 100, 85);
    p.diffusion = bounded(p.diffusion, 0, 100, 100);
    p.hfRatio = bounded(p.hfRatio, .1f, 2, .8f);
    p.hfLevel = bounded(p.hfLevel, -90, 0, -6);
    p.earlyLevel = bounded(p.earlyLevel, 0, 1, .25f);
    p.earlyDelay = bounded(p.earlyDelay, 0, 300, 7);
    p.wet = bounded(p.wet, 0, 1, .25f);
    p.dry = bounded(p.dry, 0, 1, 1);
    p.lowCut = bounded(p.lowCut, 20, 2000, 20);
    p.highCut = bounded(p.highCut, 2000, 20000, 18000);
    p.width = bounded(p.width, 0, 2, 1);
    target = p;
}
void Reverb::reset() {
    for (auto& d : lines) d.clear();
    for (auto& d : allpasses) d.clear();
    for (auto& d : input) d.clear();
    damping.fill(0); lowState.fill(0); highState.fill(0);
    lowInput.fill(0); highInput.fill(0); toneState.fill(0);
    initialized = false;
}
Reverb::Coefficients Reverb::coefficients() const {
    Coefficients c;
    c.wet = target.enabled ? target.wet : 0;
    c.dry = target.enabled ? target.dry : 1;
    c.early = target.earlyLevel;
    c.predelay = target.predelay * rate / 1000;
    c.earlyDelay = target.earlyDelay * rate / 1000;
    c.diffusion = target.diffusion * .0072f;
    // Bilinear first-order filters retain a meaningful cutoff near Nyquist.
    const auto pole = [this](float hz) {
        const float k = std::tan(3.141592654f * std::min(hz, rate * .45f) / rate);
        return (1 - k) / (1 + k);
    };
    c.low = pole(target.lowCut); c.high = pole(target.highCut);
    c.tone = std::pow(10.f, target.hfLevel / 20);
    c.width = target.width;
    for (int j = 0; j < 8; ++j) {
        c.lengths[j] = baseLengths[j] * rate / 48000.f * (.35f + target.size * .013f);
        c.gain[j] = std::pow(.001f, c.lengths[j] / (rate * target.decay));
        c.hfGain[j] = std::pow(.001f, c.lengths[j] / (rate * target.decay * target.hfRatio));
    }
    return c;
}
void Reverb::process(float* stereo, int frames) {
    if (!stereo || frames <= 0) return;
    const Coefficients next = coefficients();
    if (!initialized) { previous = next; initialized = true; }
    const float dampPole = std::exp(-6.283185307f * std::min(4000.f, rate * .4f) / rate);
    for (int n = 0; n < frames; ++n) {
        const float t = float(n + 1) / frames;
        const auto blend = [t](float a, float b) { return interpolate(a, b, t); };
        float dryL = std::isfinite(stereo[2*n]) ? stereo[2*n] : 0;
        float dryR = std::isfinite(stereo[2*n+1]) ? stereo[2*n+1] : 0;
        float filtered[2];
        for (int ch = 0; ch < 2; ++ch) {
            const float x = ch ? dryR : dryL;
            const float lp = blend(previous.low, next.low), hp = blend(previous.high, next.high);
            lowState[ch] = clean(lp * lowState[ch] + (1 + lp) * .5f * (x - lowInput[ch]));
            lowInput[ch] = x;
            highState[ch] = clean(hp * highState[ch] + (1 - hp) * .5f * (lowState[ch] + highInput[ch]));
            highInput[ch] = lowState[ch];
            toneState[ch] = clean(dampPole * toneState[ch] + (1 - dampPole) * highState[ch]);
            filtered[ch] = toneState[ch] + blend(previous.tone, next.tone) * (highState[ch] - toneState[ch]);
            input[ch].push(filtered[ch]);
        }
        const float pre = blend(previous.predelay, next.predelay);
        float feedL = pre < 1 ? filtered[0] : input[0].read(pre + 1);
        float feedR = pre < 1 ? filtered[1] : input[1].read(pre + 1);
        const float diff = blend(previous.diffusion, next.diffusion);
        for (int j = 0; j < 4; ++j) {
            float& feed = j % 2 ? feedR : feedL;
            const float delayed = allpasses[j].read(diffusionLengths[j] * rate / 48000.f);
            const float out = delayed - diff * feed;
            allpasses[j].push(feed + diff * out);
            // At zero diffusion, bypass the allpass rather than leave a pure delay.
            feed = interpolate(feed, out, diff / .72f);
        }
        float v[8];
        float lateL = 0, lateR = 0;
        for (int j = 0; j < 8; ++j) {
            const float x = lines[j].read(blend(previous.lengths[j], next.lengths[j]));
            lateL += x * (j % 2 ? -1.f : 1.f);
            lateR += x * ((j / 2) % 2 ? -1.f : 1.f);
            damping[j] = clean(dampPole * damping[j] + (1 - dampPole) * x);
            v[j] = damping[j] * blend(previous.gain[j], next.gain[j]) +
                (x - damping[j]) * blend(previous.hfGain[j], next.hfGain[j]);
        }
        // Normalized Hadamard matrix: energy-preserving feedback mixing.
        for (int span = 1; span < 8; span *= 2) {
            for (int j = 0; j < 8; j += span * 2) {
                for (int k = 0; k < span; ++k) {
                    const float a = v[j+k], b = v[j+k+span];
                    v[j+k] = a + b; v[j+k+span] = a - b;
                }
            }
        }
        for (int j = 0; j < 8; ++j) {
            const float injection = (j % 2 ? feedR : feedL) * (j < 4 ? .25f : -.25f);
            lines[j].push(injection + v[j] * .353553391f);
        }
        float earlyL = 0, earlyR = 0;
        const float er = pre + blend(previous.earlyDelay, next.earlyDelay);
        constexpr float taps[] = {0, .005f, .011f, .017f, .029f, .043f};
        for (int j = 0; j < 6; ++j) {
            const float delay = er + taps[j] * rate + 1;
            earlyL += input[j % 2].read(delay) * (.26f / (1 + j * .35f));
            earlyR += input[1 - j % 2].read(delay + j * .0007f * rate) * (.26f / (1 + j * .35f));
        }
        const float early = blend(previous.early, next.early);
        const float l = lateL * .5f + earlyL * early, r = lateR * .5f + earlyR * early;
        const float mid = (l+r) * .5f, side = (l-r) * .5f * blend(previous.width, next.width);
        const float wet = blend(previous.wet, next.wet), dry = blend(previous.dry, next.dry);
        stereo[2*n] = std::clamp(dryL * dry + (mid+side) * wet, -1.f, 1.f);
        stereo[2*n+1] = std::clamp(dryR * dry + (mid-side) * wet, -1.f, 1.f);
    }
    previous = next;
}
}
