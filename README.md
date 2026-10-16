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
| Ecualizador, graves y ganancia | Sí, si el dispositivo los admite | Solo sesiones compatibles que la otra app anuncie |
| Reverberación y balance | Sí, si hay soporte de reverb | No |
| Volumen multimedia | Volumen del sistema | Volumen del sistema |

Para otras apps: activa el motor primero y luego inicia o reinicia su reproducción. Se escuchan los broadcasts `OPEN_AUDIO_EFFECT_CONTROL_SESSION` y `CLOSE_AUDIO_EFFECT_CONTROL_SESSION` mientras el servicio está activo. No se utiliza el antiguo truco de insertar un ecualizador en la sesión global 0. No se captura ni graba el audio del teléfono.

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

Referencias: [AudioEffect](https://developer.android.com/reference/android/media/audiofx/AudioEffect), [PresetReverb](https://developer.android.com/reference/android/media/audiofx/PresetReverb), [LoudnessEnhancer](https://developer.android.com/reference/android/media/audiofx/LoudnessEnhancer).
