package com.audiowav.audiowav

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pickerResult: MethodChannel.Result? = null
    private var panelRequested = false

    override fun onCreate(savedInstanceState: Bundle?) {
        panelRequested = intent?.action == AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL
        super.onCreate(savedInstanceState)
        openEffectPanel(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openEffectPanel(intent)
    }

    private fun openEffectPanel(intent: Intent?) {
        if (intent?.action != AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL) return
        panelRequested = true
        val prefs = getSharedPreferences("studio", MODE_PRIVATE)
        val saved = JSONObject(prefs.getString("settings", "{}") ?: "{}")
        saved.put("enabled", true)
        prefs.edit().putString("settings", saved.toString()).apply()
        startEngine(Intent(this, AudioService::class.java).apply {
            action = AudioService.OPEN_SESSION
            putExtra(AudioEffect.EXTRA_AUDIO_SESSION, intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1))
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "audiowav/audio")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initialize" -> {
                            if (AudioService.instance == null && !panelRequested) {
                                val prefs = getSharedPreferences("studio", MODE_PRIVATE)
                                val saved = JSONObject(prefs.getString("settings", "{}") ?: "{}")
                                saved.put("enabled", false)
                                prefs.edit().putString("settings", saved.toString()).apply()
                            }
                            result.success(snapshot())
                        }
                        "snapshot" -> result.success(snapshot())
                        "configure" -> {
                            val config = JSONObject(call.arguments as Map<*, *>).toString()
                            getSharedPreferences("studio", MODE_PRIVATE).edit().putString("settings", config).apply()
                            if (AudioService.instance != null) {
                                AudioService.instance?.configure()
                            } else if (JSONObject(config).optBoolean("enabled")) {
                                startEngine(Intent(this, AudioService::class.java))
                            }
                            result.success(null)
                        }
                        "openFile" -> {
                            if (pickerResult != null) { result.error("PICKER_BUSY", "Ya hay un selector de archivos abierto.", null) }
                            else {
                                pickerResult = result
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    type = "audio/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivityForResult(intent, 42)
                            }
                        }
                        "togglePlayback" -> { AudioService.instance?.togglePlayback(); result.success(null) }
                        "seek" -> { AudioService.instance?.seek((call.arguments as Number).toInt()); result.success(null) }
                        "volume" -> {
                            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                            val value = (call.arguments as Number).toDouble().coerceIn(0.0, 1.0)
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, (value * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(), 0)
                            result.success(null)
                        }
                        "stop" -> { stopService(Intent(this, AudioService::class.java)); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    pickerResult = null
                    result.error("AUDIO_ERROR", error.localizedMessage ?: "No se pudo acceder al audio.", null)
                }
            }
    }

    private fun startEngine(intent: Intent) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 43)
        }
        startForegroundService(intent)
    }

    private fun snapshot(): Map<String, Any?> {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        val data = (AudioService.instance?.snapshot() ?: mapOf("running" to false,
            "advancedDetection" to (checkSelfPermission("android.permission.DUMP") == PackageManager.PERMISSION_GRANTED),
            "capabilities" to mapOf("equalizer" to false, "bass" to false, "gain" to false, "reverb" to false))).toMutableMap()
        data["volume"] = audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val saved = JSONObject(getSharedPreferences("studio", MODE_PRIVATE).getString("settings", "{}") ?: "{}")
        data["settings"] = mapOf(
            "enabled" to saved.optBoolean("enabled"), "preset" to saved.optString("preset", "Plano"),
            "bands" to List(5) { saved.optJSONArray("bands")?.optDouble(it, 0.0) ?: 0.0 },
            "bass" to saved.optDouble("bass", 0.0), "gain" to saved.optDouble("gain", 0.0),
            "balance" to saved.optDouble("balance", 0.0), "reverb" to saved.optInt("reverb", 0), "wet" to saved.optDouble("wet", 0.25)
        )
        return data
    }

    @Deprecated("Uses the platform document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 42) return
        val callback = pickerResult
        pickerResult = null
        try {
            val uri = data?.data
            if (resultCode == RESULT_OK && uri != null) {
                var title = "Archivo de audio"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) title = cursor.getString(0) ?: title
                }
                startEngine(Intent(this, AudioService::class.java).apply {
                    action = AudioService.OPEN_FILE
                    putExtra("uri", uri.toString())
                    putExtra("title", title)
                })
            }
            callback?.success(null)
        } catch (error: Exception) { callback?.error("FILE_ERROR", error.localizedMessage, null) }
    }

    override fun onDestroy() {
        pickerResult?.error("CANCELLED", "El selector se cerró.", null)
        pickerResult = null
        super.onDestroy()
    }
}
