# Audiowav

Estudio de audio móvil construido con Flutter y un motor nativo Kotlin para Android.

## Funciones

- Ecualizador de cinco controles (60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz), de −12 a +12 dB. Se interpolan en escala logarítmica a las bandas reales de Android.
- Presets Plano, Potente, Rock, Voces, Electrónica y Acústico; ajuste personalizado.
- Refuerzo de graves y ganancia de hasta +12 dB mediante los efectos nativos del dispositivo.
- Reverberación: habitaciones pequeña/mediana/grande, salas mediana/grande y placa, con mezcla ajustable.
- Balance estéreo y control del volumen multimedia del teléfono.
- Reproductor local: selección de archivos mediante el selector del sistema, reproducción, pausa y búsqueda.
- Servicio en primer plano con notificación para reproducir en segundo plano y detener el motor.
- Ajustes guardados en el dispositivo. Funciona sin cuenta, backend ni conexión de red.

## Compatibilidad y alcance

**Android 8.0 o posterior** es la plataforma funcional de esta primera versión. Los efectos disponibles dependen del fabricante, la ruta de salida y el control de la sesión. Los controles sin soporte se deshabilitan.

| Control | Archivos en Audiowav | Otras aplicaciones |
| --- | --- | --- |
| Ecualizador, graves y ganancia | Sí, si el dispositivo los admite | Sesiones compartidas o detección avanzada por DUMP |
| Reverberación | Sí, si hay soporte de reverb | Requiere reverb de inserción del fabricante |
| Balance | Sí | No |
| Volumen multimedia | Volumen del sistema | Volumen del sistema |

Para otras apps: activa el motor y reproduce música. Los controles se habilitan cuando existe una sesión conectada con un efecto controlable, y no simplemente porque el dispositivo anuncie un efecto instalado. Se siguen admitiendo los broadcasts `OPEN_AUDIO_EFFECT_CONTROL_SESSION` y `CLOSE_AUDIO_EFFECT_CONTROL_SESSION`.

### Detección avanzada de otras apps

Muchas apps no anuncian sus sesiones. Para encontrarlas automáticamente, conecta el teléfono por USB con depuración habilitada y concede una vez este permiso desde una PC:

```sh
adb shell pm grant com.audiowav.audiowav android.permission.DUMP
```

`DUMP` permite leer diagnósticos del sistema. Audiowav consulta únicamente `dumpsys media.audio_flinger` en un hilo de trabajo mientras el motor está activo, extrae las sesiones de música/juegos de las tablas de reproducción, excluye su propio reproductor y libera los efectos al desaparecer las sesiones. No guarda ni transmite el volcado. El permiso permanece hasta revocarlo o desinstalar:

```sh
adb shell pm revoke com.audiowav.audiowav android.permission.DUMP
```

La reverb externa usa la API pública `EnvironmentalReverb` sobre cada sesión y verifica que Android haya seleccionado un efecto **de inserción**, con ambientes y nivel ajustables. Esto depende del fabricante. Si la creación, el modo de conexión o los parámetros fallan, la app informa que la reverberación externa no está disponible. La reverb local conserva el efecto auxiliar conectado al `MediaPlayer`.

Los cambios de controles se envían durante el arrastre, con un intervalo de 40 ms entre envíos y conservación del último valor. No se utiliza la sesión global 0 para insertar efectos. No se captura ni graba audio.

El aumento de ganancia actúa sobre la señal, no aumenta la potencia física del altavoz ni elimina los límites de volumen de Android. La ganancia y los graves altos pueden distorsionar.

**iOS:** se incluye el proyecto base y la interfaz muestra que el motor no está implementado. No se presenta como un procesador global para iPhone. Implementar procesamiento dentro de un reproductor iOS requiere un motor propio y validación en macOS/Xcode.

## Ejecutar

Requisitos: Flutter estable con Dart 3.13.5 o posterior, SDK Android y JDK compatible con Gradle. Conecta un teléfono con depuración USB o inicia un emulador.

```sh
flutter pub get
flutter run
```

Crear un APK de desarrollo:

```sh
flutter build apk --debug
```

Salida: `build/app/outputs/flutter-apk/app-debug.apk`. La firma de producción debe configurarse antes de distribuir en una tienda; la configuración generada usa una clave de desarrollo.

## Validación

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions ejecuta los mismos controles y adjunta el APK de desarrollo como artefacto.

Consulta [la guía de pruebas en dispositivo](docs/device-testing.md) para verificar el procesamiento audible. Las pruebas de Flutter cubren la interfaz y el contrato del canal, pero no verifican el sonido del hardware.

## Código

- `lib/studio_screen.dart`: interfaz en español, con tema oscuro y controles accesibles.
- `lib/audio_controller.dart`: estado, presets, comunicación con Android y agrupación de cambios del usuario.
- `android/app/src/main/kotlin/com/audiowav/audiowav/MainActivity.kt`: canal `audiowav/audio` y selector de archivos.
- `AudioService.kt`: reproducción, sesiones externas, notificación, foco de audio y reverberación auxiliar.
- `EffectRack.kt`: efectos por sesión e interpolación del ecualizador.
- `PlaybackSessions.kt`: parser de sesiones para detección avanzada; pruebas JVM en `android/app/src/test`.
- `InsertReverb.kt`: adaptación opcional de la reverberación de inserción del fabricante.

La versión 1.0.1 se comprobó en un Moto g24 power con Android 14 sobre una sesión externa de RVX Music: ecualizador, graves, ganancia y reverb conectados simultáneamente, con lectura de sus parámetros reales. Detalles en la guía de pruebas.

Referencias: [AudioEffect](https://developer.android.com/reference/android/media/audiofx/AudioEffect), [PresetReverb](https://developer.android.com/reference/android/media/audiofx/PresetReverb), [LoudnessEnhancer](https://developer.android.com/reference/android/media/audiofx/LoudnessEnhancer).
