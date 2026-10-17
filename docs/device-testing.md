# Pruebas en Android

Usar un teléfono físico y auriculares estéreo. Comenzar con volumen bajo. Un emulador sirve para verificar navegación y servicio, pero no representa los efectos disponibles en cada teléfono.

1. Abrir Audiowav después de una instalación limpia. No debe iniciar el servicio automáticamente.
2. Activar el motor y conceder notificaciones si Android lo solicita. Verificar la notificación persistente y el botón Detener.
3. Abrir un archivo estéreo WAV, MP3 o AAC desde el selector. Cancelar el selector debe devolver a la app sin error. Probar también un archivo inválido: debe mostrar un mensaje y permitir abrir otro.
4. Verificar reproducción/pausa, búsqueda, duración y reproducción con pantalla apagada. Probar los botones de la notificación.
5. Cambiar presets y bandas. Comparar motor activado/desactivado con la misma canción. Los controles de bandas deben responder también en dispositivos con diferente número de bandas.
6. Ajustar graves y ganancia gradualmente. Los efectos ausentes o sin control deben aparecer deshabilitados.
7. Probar todos los ambientes de reverb y su mezcla con audio local. En una sesión externa, comprobar la reverb de inserción si el fabricante y Android la permiten; si falla, debe mostrarse el motivo. Comprobar balance izquierdo, centro y derecho con un archivo estéreo conocido.
8. Cambiar volumen y comprobar que cambia el volumen multimedia de Android. No debe modificar el volumen de llamadas.
9. Desconectar auriculares: la reproducción local debe pausarse. Iniciar otra app que tome el foco de audio: Audiowav debe pausar o atenuar según la solicitud y respetar la pérdida permanente de foco.
10. Con el motor activo, iniciar reproducción en una app que anuncie `OPEN_AUDIO_EFFECT_CONTROL_SESSION`. Verificar que sube el contador y que ecualizador/graves/ganancia responden. Luego conceder `DUMP` según el README y probar una app que no anuncie sesiones: debe conectarse automáticamente. Al liberar las pistas debe bajar el contador. Sin sesiones, no deben habilitarse efectos ni mostrarse como conectados.
11. Salir y volver a abrir la interfaz mientras se reproduce: debe reconectarse al servicio. Detener desde la notificación: debe liberar audio y efectos. Abrir de nuevo no debe reiniciar el servicio por sí solo.
12. Reiniciar la app y comprobar la persistencia de presets, bandas, graves, ganancia, balance y reverb. El volumen no se eleva automáticamente al iniciar.
13. Arrastrar continuamente una banda o la mezcla de reverb: los cambios deben aplicarse mientras se mueve el dedo, sin esperar a soltar.
14. Revocar `DUMP`, detener y reactivar el motor: solo deben seguir disponibles las sesiones que otras apps compartan explícitamente.

Registrar modelo, versión Android, ruta de salida y efectos disponibles. El soporte de sesiones externas y de reverb debe validarse por dispositivo.

## DSP local (1.2.0)

1. Abrir un archivo mono o estéreo desde el reproductor. El panel debe indicar `DSP propio · Archivo local` y habilitar PRE DEL, SIZE, L.CUT, H.CUT, DRY y WIDTH.
2. Activar el motor y la reverb. Con WET en cero, DRY debe controlar únicamente la señal original; con DRY en cero se escucha solo el efecto. Bypass debe recuperar la señal original.
3. Comparar un predelay corto y largo, ER y su retardo, filtros y anchura. WIDTH en cero debe hacer mono el retorno, conservando el estéreo original según DRY.
4. Pausar, esperar y reanudar; buscar otra posición, también estando en pausa. La cola anterior no debe reaparecer tras buscar.
5. Dejar terminar el archivo, comprobar la cola y volver a reproducir. Abrir otro archivo y detener el servicio deben liberar la salida anterior.
6. Guardar un preset con filtros, DRY y anchura; comprobarlo tras cerrar y abrir la interfaz.
7. Con audio de otra app y sin archivo abierto, los controles nuevos no deben anunciar soporte externo.

La suite de dispositivo crea archivos de prueba privados, sin capturar audio del usuario. Comprueba el puente JNI con señales conocidas y reproduce WAV mono, WAV estéreo y AAC generado en el teléfono. Comprueba avance, pausa, búsqueda en pausa, reanudación, fin, cola y repetición. La salida de prueba usa ganancia baja.

```sh
cd android
./gradlew assembleDebug assembleDebugAndroidTest testDebugUnitTest -Ptarget-platform=android-arm64
cd ..
adb install -r build/app/outputs/apk/debug/app-debug.apk
adb install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.audiowav.audiowav.test/com.audiowav.audiowav.DspInstrumentation
```

El resultado esperado incluye `All 4 device checks passed`. Los tiempos máximos por bloque miden tiempo de pared alrededor de la llamada DSP; pueden incluir pausas del planificador. El contador de interrupciones (`underruns`) corresponde a la salida probada. Estas medidas no equivalen a una prueba acústica, una medición completa de latencia ni una comparación con Fruity Reeverb 2.

### Resultado de la versión 1.2.0 en el Moto g24 power

El 16 de octubre de 2026, en Android 14, pasaron las cuatro comprobaciones del dispositivo: el puente JNI aplicó los niveles DRY/WET esperados y el reproductor completó pausa, búsqueda en pausa, reanudación, final con cola y repetición con WAV estéreo, WAV mono y AAC/M4A. Todos los archivos se generaron para la prueba a 48 kHz.

| Archivo | Máximo observado por llamada DSP | Contador al arrancar | Tras buscar | Al terminar | Tras repetir |
| --- | --- | --- | --- | --- | --- |
| WAV estéreo | 2019 µs | 0 | 0 | 1 | 1 |
| WAV mono | 3235 µs | 0 | 0 | 1 | 1 |
| AAC/M4A | 4541 µs | 0 | 0 | 1 | 1 |

Los bloques completos de 1024 muestras representan 21,33 ms a 48 kHz. El contador no aumentó durante el arranque o la búsqueda comprobados; su incremento único coincide con el vaciado de la salida al terminar el archivo, y no volvió a aumentar tras repetir. La salida se llena antes de arrancar para evitar comenzar con un paquete AAC parcialmente recortado por la búsqueda. Estos resultados describen la secuencia ensayada, no garantizan ausencia de interrupciones bajo cualquier carga o ruta de audio.

También pasaron 14 pruebas Flutter, 10 comprobaciones de señales del motor C++ y 4 pruebas JVM. Se compilaron las bibliotecas nativas para ARM64, ARM de 32 bits y x86_64.

Se comprobó además la interfaz instalada con un archivo local de 44,1 kHz: aparecieron los controles PRE DEL, SIZE, DRY, L.CUT, H.CUT y WIDTH. El servicio informó `localDsp=true` y más de cinco millones de muestras estéreo procesadas. Se consultó el estado del motor sin registrar el contenido del archivo.

## Comprobación realizada el 16 de octubre de 2026

En un Moto g24 power con Android 14 se verificó la conexión automática a la sesión de RVX Music mediante DUMP. Sin archivo local abierto, los diagnósticos del motor devolvieron simultáneamente control de ecualizador, graves, ganancia y reverb. Lecturas reales de los efectos: bandas `[400, 200, 200, 400, 900]` mB, graves 469/1000, ganancia activada a 582 mB y reverb activada con decaimiento de 1400 ms. Los valores coincidieron con los ajustes de la interfaz. Esta comprobación valida la conexión y los parámetros del motor; la percepción audible requiere escuchar el equipo.

Consultar los valores aplicados, sin capturar audio:

```sh
adb shell dumpsys activity service com.audiowav.audiowav/.AudioService
```

Si se reinstala la app mientras otra app mantiene una sesión abierta, Android puede conservar temporalmente motores sin cliente y rechazar una conexión nueva. Reiniciar la reproducción/app de música una vez libera esa sesión. Los ajustes posteriores se aplican en vivo sin reiniciar.
