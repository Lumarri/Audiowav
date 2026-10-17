package com.audiowav.audiowav

import org.json.JSONObject

object CaptureDspSettings {
    fun from(settings: JSONObject, originalMuted: Boolean): FloatArray {
        return forRoute(DspSettings.from(settings), originalMuted)
    }

    fun forRoute(values: FloatArray, originalMuted: Boolean): FloatArray {
        val parameters = values.copyOf()
        if (!originalMuted) {
            // An additive return must never repeat the dry signal, including bypass.
            if (parameters[0] == 0f) parameters[9] = 0f
            parameters[0] = 1f
            parameters[10] = 0f
        }
        return parameters
    }
}
