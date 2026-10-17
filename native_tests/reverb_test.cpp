#include "reverb.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

using audiowav::Parameters;
using audiowav::Reverb;
namespace {
constexpr int rate = 48000;
constexpr double pi = 3.14159265358979323846;
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
void render(Reverb& engine, std::vector<float>& samples, int block = 512) {
    for (int frame = 0; frame < int(samples.size()/2); frame += block)
        engine.process(samples.data() + frame*2, std::min(block, int(samples.size()/2) - frame));
}
double energy(const std::vector<float>& data, double from = 0, double to = -1) {
    int first = int(from * rate) * 2;
    int last = to < 0 ? int(data.size()) : std::min(int(data.size()), int(to * rate) * 2);
    double total = 0;
    for (int i = first; i < last; ++i) total += double(data[i]) * data[i];
    return total;
}
std::vector<float> impulse(Parameters p, int seconds = 3) {
    Reverb engine(rate); engine.configure(p);
    std::vector<float> data(rate * seconds * 2, 0);
    data[0] = .5f; data[1] = .25f;
    render(engine, data);
    return data;
}
double sineEnergy(Parameters p, float hz) {
    Reverb engine(rate); engine.configure(p);
    std::vector<float> data(rate * 2 * 2);
    for (int i = 0; i < int(data.size()/2); ++i)
        data[2*i] = data[2*i+1] = .05f * std::sin(2*pi*hz*i/rate);
    render(engine, data);
    return energy(data, 1);
}
void writeWave(const char* filename) {
    // A generated chord, never captured phone audio.
    Parameters p; p.enabled = true; p.decay = 3.5f; p.predelay = 35;
    p.wet = .5f; p.lowCut = 140; p.highCut = 8000; p.dry = .8f;
    Reverb engine(rate); engine.configure(p);
    std::vector<float> data(rate * 8 * 2, 0);
    for (int i = 0; i < rate * 2; ++i) {
        const float envelope = .06f * std::exp(-3.f*i/rate);
        for (float hz : {220.f, 277.18f, 329.63f}) {
            data[2*i] += envelope * std::sin(2*pi*hz*i/rate);
            data[2*i+1] += envelope * std::sin(2*pi*(hz*1.002f)*i/rate);
        }
    }
    render(engine, data);
    std::ofstream out(filename, std::ios::binary);
    const auto u32 = [&out](uint32_t v) { for (int j=0;j<4;++j) out.put(char(v>>(j*8))); };
    const auto u16 = [&out](uint16_t v) { out.put(char(v));out.put(char(v>>8)); };
    const auto bytes = uint32_t(data.size()*4);
    out.write("RIFF",4);u32(36+bytes);out.write("WAVEfmt ",8);u32(16);
    u16(3);u16(2);u32(rate);u32(rate*8);u16(8);u16(32);out.write("data",4);u32(bytes);
    out.write(reinterpret_cast<const char*>(data.data()), bytes);
    require(bool(out), "Cannot write demo WAV");
}
}

int main(int argc, char** argv) {
    try {
        Parameters p;
        {
            Reverb engine(rate); engine.configure(p);
            std::vector<float> input(4096);
            for (int i=0;i<4096;++i) input[i] = .3f * std::sin(i*.31f);
            auto output = input; render(engine, output);
            require(input == output, "Bypass changed the original signal");
        }
        std::cout << "PASS bypass preserves samples\n";
        p.enabled = true; p.wet = 0; p.dry = 0;
        require(energy(impulse(p)) == 0, "DRY and WET zero did not mute output");
        p.dry = .5f;
        auto dry = impulse(p, 1);
        require(dry[0] == .25f && dry[1] == .125f, "Independent dry gain failed");
        require(energy(dry, .01) == 0, "WET zero leaked a tail");
        std::cout << "PASS independent dry/wet\n";
        p.dry = 0; p.wet = 1; p.predelay = 100; p.earlyDelay = 0; p.earlyLevel = 1;
        auto delayed = impulse(p);
        require(energy(delayed, 0, .099) == 0, "Predelay leaked an early signal");
        require(energy(delayed, .1, .2) > 1e-7, "Predelay did not produce a return");
        std::cout << "PASS predelay gates the wet signal\n";
        {
            Parameters early = p; early.predelay = 0; early.size = 100;
            early.earlyDelay = 10;
            const auto reflections = impulse(early, 1);
            early.earlyLevel = 0;
            require(energy(reflections, .005, .03) > 1e-7, "Early reflections are missing");
            require(energy(impulse(early, 1), 0, .03) == 0, "Early level zero still produces reflections");
            early.earlyLevel = 1; early.earlyDelay = 80;
            require(energy(impulse(early, 1), 0, .03) == 0, "Early reflection delay did not move the taps");
        }
        std::cout << "PASS early reflection level and delay\n";
        p.width = 0;
        auto mono = impulse(p);
        for (size_t i=0;i<mono.size();i+=2) require(mono[i] == mono[i+1], "Width zero is not mono");
        p.width = 1;
        auto stereo = impulse(p);
        double side = 0;
        for (size_t i=0;i<stereo.size();i+=2) side += std::pow(stereo[i]-stereo[i+1],2);
        require(side > 1e-7, "Stereo return has no side energy");
        std::cout << "PASS stereo width\n";
        p.predelay = 0; p.decay = .2f; p.earlyLevel = 0;
        auto shortTail = impulse(p);
        p.decay = 3;
        auto longTail = impulse(p);
        const double shortEnergy = energy(shortTail, .8, 1.3), longEnergy = energy(longTail, .8, 1.3);
        require(longEnergy > std::max(1e-12, shortEnergy * 100), "Long decay does not retain more late energy");
        std::cout << "PASS decay: short=" << shortEnergy << " long=" << longEnergy << '\n';
        p.decay = .1f; p.earlyLevel = 1; p.highCut = 20000;
        const double bright = sineEnergy(p, 8000);
        p.highCut = 2000;
        require(sineEnergy(p, 8000) < bright * .3, "High cut does not attenuate high frequencies");
        p.highCut = 18000; p.lowCut = 20;
        const double fullBass = sineEnergy(p, 100);
        p.lowCut = 2000;
        require(sineEnergy(p, 100) < fullBass * .05, "Low cut does not attenuate bass");
        std::cout << "PASS low/high filters\n";
        {
            Reverb engine(rate); engine.configure(p);
            std::vector<float> data(4096, .1f); render(engine, data);
            engine.reset(); data.assign(4096, 0); render(engine, data);
            require(energy(data) == 0, "Reset retained audio after seeking");
        }
        std::cout << "PASS reset clears the delay network\n";
        {
            std::vector<float> source(20000);
            for (int i=0;i<20000;++i) source[i] = .1f*std::sin(i*.17f);
            auto a=source,b=source;
            Reverb first(rate), second(rate); first.configure(p); second.configure(p);
            render(first,a,127); render(second,b,1024);
            for (size_t i=0;i<a.size();++i) require(std::abs(a[i]-b[i]) < 1e-6f, "DSP depends on decoder block size");
        }
        std::cout << "PASS block size invariance\n";
        for (int sampleRate : {8000, 44100, 48000, 96000}) {
            Reverb engine(sampleRate);
            std::vector<float> block(2048, 0);
            for (int j=0;j<500;++j) {
                Parameters extreme; extreme.enabled = true; extreme.dry = 0; extreme.wet = 1;
                extreme.decay = j%2 ? 20 : .1f; extreme.size = j%3 ? 100 : 0;
                extreme.hfRatio = j%2 ? 2 : .1f; extreme.diffusion = j%5 ? 100 : 0;
                extreme.predelay = j%7 ? 0 : 100; extreme.width = 2;
                if (j == 5) extreme.highCut = std::numeric_limits<float>::quiet_NaN();
                engine.configure(extreme);
                std::fill(block.begin(),block.end(),0);
                if (j < 10) block[0] = .25f;
                engine.process(block.data(),1024);
                for (float v : block) require(std::isfinite(v) && std::abs(v)<=1, "Unstable output at parameter extremes");
            }
        }
        std::cout << "PASS finite output through parameter extremes and sample rates\n";
        if (argc > 1) { writeWave(argv[1]); std::cout << "Rendered demo: " << argv[1] << '\n'; }
        std::cout << "All 10 DSP checks passed\n";
    } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; return 1; }
}
