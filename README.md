# Audiowav

Estudio de audio móvil construido con Flutter, Kotlin y un motor de reverberación C++ para Android.

## Funciones

- Ecualizador de cinco controles (60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz), de −12 a +12 dB. Se interpolan en escala logarítmica a las bandas reales de Android.
- Presets Plano, Potente, Rock, Voces, Electrónica y Acústico; ajuste personalizado.
- Refuerzo de graves y ganancia de hasta +12 dB mediante los efectos nativos del dispositivo.
- Reverb Studio: motor DSP estéreo propio para archivos locales y captura autorizada de otras apps, con decaimiento, predelay, tamaño, difusión, amortiguación, reflexiones, filtros L.CUT/H.CUT, anchura y WET. DRY independiente en archivos locales y en captura con control confirmado del original. Incluye presets personales. [Alcance y diferencias con Fruity Reeverb 2](docs/reverb-studio.md).
- Balance estéreo y control del volumen multimedia del teléfono.
- Reproductor local: selección de archivos mediante el selector del sistema, reproducción, pausa y búsqueda.
- Servicio en primer plano con notificación para reproducir en segundo plano y detener el motor.
- Ajustes guardados en el dispositivo. Funciona sin cuenta, backend ni conexión de red.

## Compatibilidad y alcance

**Android 8.0 o posterior** es la plataforma funcional de esta primera versión. Los efectos disponibles dependen del fabricante, la ruta de salida y el control de la sesión. Los controles sin soporte se deshabilitan.

| Control | Archivos en Audiowav | Otras aplicaciones |
| --- | --- | --- |
| Ecualizador, graves y ganancia | Sí, si el dispositivo los admite | Sesiones compartidas o detección avanzada por DUMP |
| Reverberación | DSP propio C++, independiente de la reverb del fabricante | DSP en vivo con captura autorizada; alternativa nativa según fabricante |
| Filtros de reverb y anchura | Sí | Sí, con DSP en vivo y señal confirmada |
| DRY | Sí | Con DSP en vivo, si se confirma el control del original |
| Balance | Sí | Con DSP en vivo |
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

Sin DSP en vivo, la reverb externa usa la API pública `EnvironmentalReverb` sobre cada sesión y verifica que Android haya seleccionado un efecto **de inserción**. Esto depende del fabricante. Si la creación, el modo de conexión o los parámetros fallan, la app informa que esa reverberación no está disponible. Los archivos locales se decodifican con `MediaExtractor`/`MediaCodec`, pasan por el DSP propio y salen por `AudioTrack`. El modo en vivo descrito abajo también conecta el motor propio a una captura autorizada.

El reproductor admite archivos mono y estéreo que Android pueda extraer y decodificar a PCM de 16 bits o flotante, de 8 a 192 kHz. El audio multicanal y otros formatos PCM muestran un error explícito. La cola de reverb puede continuar tras terminar la canción; buscar otra posición borra los retardos. El DSP no contiene código ni algoritmos propietarios de Fruity Reeverb 2 y no se promete equivalencia sonora o de rendimiento.

Los cambios de controles se envían durante el arrastre, con un intervalo de 40 ms entre envíos y conservación del último valor. No se utiliza la sesión global 0 para insertar efectos. El motor habitual no captura audio.

### Prueba de audio interno (1.3.0, Android 10+)

En **OTRAS APPS → Probar audio de otras apps**, elige la app que está reproduciendo música y pulsa **Probar 20 segundos**. Se muestran únicamente las variantes conocidas de YouTube Music, Spotify y Deezer instaladas para el usuario actual. Android pide `RECORD_AUDIO` y una autorización nueva de `MediaProjection` por prueba; no se conceden mediante ADB ni se reutiliza el token.

Un servicio separado, visible con notificación y botón de detención, captura PCM únicamente del UID elegido mediante `AudioPlaybackCaptureConfiguration`. No se abre una entrada de micrófono, no se crea una captura de imágenes, no se guarda ni transmite el PCM y no se reproduce. Solo se conservan en memoria contadores y mediciones de pico/RMS. Se detiene a los 20 segundos, al pulsar detener o cuando Android revoca la proyección.

Recibir señal durante al menos tres bloques confirma que llegó audio en esa ejecución. Un resultado silencioso es inconcluso: la fuente podría estar pausada, ser otra app o impedir la captura. **Esta prueba todavía no conecta el DSP a otras apps ni sustituye su salida original**; sirve para decidir si se puede avanzar con un retorno de reverb y evaluar su retardo. Más detalles y casos manuales en [la guía del dispositivo](docs/device-testing.md).

### Reverb Studio en vivo (1.4.0, Android 10+, experimental)

Con música reproduciéndose, selecciona **Otras apps** en Reverb Studio y pulsa **Activar DSP** para la app indicada, o elige la app en el panel inferior y pulsa **Activar Reverb Studio en vivo**. Android solicita una autorización nueva, independiente de la prueba de 20 segundos. El modo en vivo continúa hasta pulsar detener, desactivar el motor, abrir un archivo local, desconectar los auriculares o perder la autorización.

La ruta es `AudioRecord` limitado al UID elegido → PCM flotante → nuestro DSP C++ → salida PCM16 con `AudioTrack`. No se pide foco de audio que pause la fuente. La salida propia impide su captura y se excluye de la detección de sesiones. Los controles se habilitan solo después de recibir señal y preparar la salida. El DSP recibe los ajustes durante el arrastre; los efectos Android de EQ, graves y ganancia se aplican a su salida si el teléfono los admite.

Con `DUMP`, se identifican exclusivamente las sesiones activas del UID seleccionado. `DynamicsProcessing` intenta atenuar ese original mientras Audiowav reproduce la mezcla procesada; DRY se habilita únicamente con control y ganancia confirmados. Si no se puede controlar el original, el DSP envía solo WET y DRY permanece fijo. La reverberación Android se desactiva mientras actúa el DSP propio para evitar añadir dos motores. Fallos, detención y pérdida de control liberan la atenuación del original. Esta ruta añade latencia y requiere validación audible en cada teléfono; no ofrece equivalencia con Fruity Reeverb 2.

El aumento de ganancia actúa sobre la señal, no aumenta la potencia física del altavoz ni elimina los límites de volumen de Android. La ganancia y los graves altos pueden distorsionar.

**iOS:** se incluye el proyecto base y la interfaz muestra que el motor no está implementado. No se presenta como un procesador global para iPhone. Implementar procesamiento dentro de un reproductor iOS requiere un motor propio y validación en macOS/Xcode.

## Ejecutar

Requisitos: Flutter estable con Dart 3.13.5 o posterior, SDK Android, NDK requerido por Flutter, CMake 3.22.1 y JDK compatible con Gradle. Conecta un teléfono con depuración USB o inicia un emulador.

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
cmake -S native_tests -B build/native-tests -DCMAKE_BUILD_TYPE=Release
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure
flutter build apk --debug
```

GitHub Actions ejecuta los mismos controles y adjunta el APK de desarrollo como artefacto.

Consulta [la guía de pruebas en dispositivo](docs/device-testing.md) para verificar el procesamiento audible. Las pruebas de Flutter cubren la interfaz y el contrato del canal, pero no verifican el sonido del hardware.

## Código

- `lib/studio_screen.dart`: interfaz en español, con tema oscuro y controles accesibles.
- `lib/audio_controller.dart`: estado, presets, comunicación con Android y agrupación de cambios del usuario.
- `android/app/src/main/kotlin/com/audiowav/audiowav/MainActivity.kt`: canal `audiowav/audio` y selector de archivos.
- `AudioService.kt`: reproducción, sesiones externas, notificación y foco de audio.
- `PcmPlayer.kt`: decodificación por bloques, salida PCM, pausa, búsqueda y cola.
- `NativeReverb.kt` y `android/app/src/main/cpp`: puente JNI y DSP propio con una red de ocho retardos y mezcla Hadamard.
- `EffectRack.kt`: efectos por sesión e interpolación del ecualizador.
- `PlaybackSessions.kt`: parser de sesiones para detección avanzada; pruebas JVM en `android/app/src/test`.
- `InsertReverb.kt`: adaptación opcional de la reverberación de inserción del fabricante.
- `CaptureProbeService.kt` y `CaptureSignalMeter.kt`: prueba voluntaria de señal interna limitada a una app, sin grabación a disco ni salida de audio.

La versión 1.0.1 se comprobó en un Moto g24 power con Android 14 sobre una sesión externa de RVX Music: ecualizador, graves, ganancia y reverb conectados simultáneamente, con lectura de sus parámetros reales. Detalles en la guía de pruebas.

Referencias: [AudioEffect](https://developer.android.com/reference/android/media/audiofx/AudioEffect), [PresetReverb](https://developer.android.com/reference/android/media/audiofx/PresetReverb), [LoudnessEnhancer](https://developer.android.com/reference/android/media/audiofx/LoudnessEnhancer).
