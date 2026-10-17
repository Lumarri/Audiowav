#pragma once
#include <array>
#include <vector>

namespace audiowav {
struct Parameters {
    bool enabled = false;
    float decay = 1.4f, predelay = 10, size = 85, diffusion = 100;
    float hfRatio = .8f, hfLevel = -6, earlyLevel = .25f, earlyDelay = 7;
    float wet = .25f, dry = 1, lowCut = 20, highCut = 18000, width = 1;
};

// Single audio-thread ownership. No allocations or locks in process().
class Reverb {
public:
    explicit Reverb(int sampleRate);
    void configure(Parameters parameters);
    void reset();
    void process(float* stereo, int frames);
private:
    struct Delay {
        std::vector<float> samples;
        int position = 0;
        explicit Delay(int capacity = 1) : samples(capacity, 0) {}
        float read(float delay) const;
        void push(float value);
        void clear();
    };
    struct Coefficients {
        float wet = 0, dry = 1, early = 0, predelay = 0, earlyDelay = 0;
        float diffusion = 0, low = 0, high = 0, tone = 0, width = 1;
        std::array<float, 8> lengths{}, gain{}, hfGain{};
    };
    int rate;
    bool initialized = false;
    Parameters target;
    Coefficients previous;
    std::array<Delay, 8> lines;
    std::array<Delay, 4> allpasses;
    std::array<Delay, 2> input;
    std::array<float, 8> damping{};
    std::array<float, 2> lowState{}, highState{}, lowInput{}, highInput{}, toneState{};
    Coefficients coefficients() const;
};
}
