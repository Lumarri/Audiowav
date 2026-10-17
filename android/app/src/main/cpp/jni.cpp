#include "reverb.h"
#include <jni.h>
#include <cstdint>
#include <new>

using audiowav::Reverb;
extern "C" JNIEXPORT jlong JNICALL
Java_com_audiowav_audiowav_NativeReverb_create(JNIEnv*, jobject, jint rate) {
    try { return reinterpret_cast<jlong>(new Reverb(rate)); } catch (...) { return 0; }
}
extern "C" JNIEXPORT void JNICALL
Java_com_audiowav_audiowav_NativeReverb_configure(JNIEnv* env, jobject, jlong handle, jfloatArray values) {
    if (!handle || env->GetArrayLength(values) != 15) return;
    jfloat p[15]; env->GetFloatArrayRegion(values, 0, 15, p);
    audiowav::Parameters settings;
    settings.enabled = p[0] > 0;
    settings.decay=p[1]; settings.predelay=p[2]; settings.size=p[3]; settings.diffusion=p[4];
    settings.hfRatio=p[5]; settings.hfLevel=p[6]; settings.earlyLevel=p[7]; settings.earlyDelay=p[8];
    settings.wet=p[9]; settings.dry=p[10]; settings.lowCut=p[11]; settings.highCut=p[12]; settings.width=p[13];
    // p[14] is reserved for a versioned parameter layout.
    reinterpret_cast<Reverb*>(handle)->configure(settings);
}
extern "C" JNIEXPORT void JNICALL
Java_com_audiowav_audiowav_NativeReverb_process(JNIEnv* env, jobject, jlong handle, jobject buffer, jint frames) {
    if (!handle || frames < 0 || env->GetDirectBufferCapacity(buffer) < jlong(frames) * 8) return;
    auto* samples = static_cast<float*>(env->GetDirectBufferAddress(buffer));
    reinterpret_cast<Reverb*>(handle)->process(samples, frames);
}
extern "C" JNIEXPORT void JNICALL
Java_com_audiowav_audiowav_NativeReverb_reset(JNIEnv*, jobject, jlong handle) {
    if (handle) reinterpret_cast<Reverb*>(handle)->reset();
}
extern "C" JNIEXPORT void JNICALL
Java_com_audiowav_audiowav_NativeReverb_destroy(JNIEnv*, jobject, jlong handle) {
    delete reinterpret_cast<Reverb*>(handle);
}
