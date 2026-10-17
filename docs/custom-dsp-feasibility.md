# Motor de reverberación propio

La referencia compartida describe técnicas generales de reverberación: líneas de retardo, filtros y redes de realimentación. No documenta el algoritmo interno de Fruity Reeverb 2 ni demuestra equivalencia de sonido o rendimiento.

## Situación del proyecto

Audiowav utiliza `EnvironmentalReverb` en `InsertReverb.kt` para otras apps. Este efecto recibe parámetros; no permite sustituir su procesamiento por una función C++. Desde 1.2.0, el reproductor propio utiliza `PcmPlayer`, que entrega muestras al DSP C++.

La detección de sesiones mediante DUMP permite conectar efectos disponibles en Android. Ese permiso no proporciona acceso a las muestras de audio ni autorización para capturarlas.

## Procesamiento propuesto

Un motor C++ que reciba bloques PCM estéreo puede implementar:

- Filtros de graves y agudos en la entrada del efecto.
- Predelay y primeras reflexiones mediante líneas de retardo.
- Difusores y una red de retardos con realimentación para la cola.
- Ajustes de decaimiento, amortiguación, difusión y anchura estéreo.
- Mezcla DRY/WET y cambios suavizados de parámetros.

La interfaz Flutter enviaría parámetros. El procesamiento de cada bloque permanecería en el hilo de audio, evitando asignaciones de memoria y llamadas a Flutter dentro de ese hilo.

[CloudSeedCore](https://github.com/GhostNoteAudio/CloudSeedCore) es una alternativa C++ de código abierto que se puede evaluar para el motor. Integrarlo requiere adaptar y medir su funcionamiento en Android; su disponibilidad no garantiza que funcione directamente como efecto del sistema.

## Rutas de audio

| Ruta | Integración necesaria | Alcance |
| --- | --- | --- |
| Archivos abiertos dentro de Audiowav | Decodificar a PCM, procesar y reproducir mediante una salida de audio propia | Control de la señal original, la reverberación y su mezcla |
| YouTube Music u otra app | Captura de reproducción con `AudioRecord` y `MediaProjection`, si la fuente lo permite | Procesar una copia; no sustituye ni silencia automáticamente la salida original |
| Efecto propio integrado en el sistema | Integración específica del dispositivo con privilegios del sistema | Fuera del alcance de instalar una APK normal; no se modifica el sistema como parte de esta evaluación |

Para la captura de otras apps, Android exige permiso `RECORD_AUDIO`, aprobación del diálogo de `MediaProjection` y una política de captura compatible en la app de origen. La fuente puede impedirla. Se deben excluir las salidas de Audiowav de la captura para evitar realimentación.

Una salida procesada de una copia añade latencia respecto al sonido original. Habría que medirla y evaluar si resulta útil como retorno de reverberación. No se promete control DRY independiente sobre YouTube Music mediante esta ruta.

## Comprobación antes de ofrecerlo como función

- Medir la respuesta a impulsos y la caída de la cola con distintas configuraciones.
- Comprobar estabilidad, filtros, mezcla y cambios de parámetros con señales de prueba.
- Medir tiempo de procesamiento por bloque, interrupciones de audio, memoria y latencia en el teléfono.
- En captura externa, comprobar primero que llegan muestras audibles de la app elegida, la revocación del permiso y la ausencia de realimentación.

El usuario eligió implementar primero la ruta local. En 1.2.0 se incorpora un motor propio, sin copiar código de las alternativas citadas. `PcmPlayer` sustituye `MediaPlayer` para entregar bloques PCM al motor C++ y reproducir el resultado mediante `AudioTrack`. No se incorporan permisos ni funciones de captura de otras apps. La ruta de YouTube Music sigue pendiente y conserva los efectos Android existentes.

En 1.3.0 se incorpora una prueba voluntaria de captura, limitada a 20 segundos y al UID de la app elegida. El usuario concede las autorizaciones en los diálogos Android. La prueba calcula nivel y presencia de señal sin conservar PCM, reproducirlo ni crear un display virtual. No aplica aún el DSP externo; falta comprobar señal real en el teléfono con autorización del usuario, y después evaluar una salida útil sin duplicación ni realimentación.

Tras la confirmación de recepción por parte del usuario, 1.4.0 agrega captura continua → DSP propio → salida PCM16. Intenta controlar únicamente el original del UID elegido con `DynamicsProcessing`; si se confirma la atenuación, habilita la mezcla DRY/WET. Si falla, libera el control y usa un retorno WET. El usuario autorizó la captura y confirmó **DSP propio · En vivo** con YouTube Music RVX. En unos 161 segundos se midieron 7.727.104 fotogramas procesados y cero underruns de salida en el Moto. El control del original falló con `AudioEffect: bad parameter value`, por lo que la ruta real usó retorno WET y DRY deshabilitado. La versión 1.4.1 cambia a la arquitectura predeterminada de DynamicsProcessing y amplía la comprobación de creación en sesión sintética nueva. La latencia total y el resultado audible no están medidos; no se presenta como equivalencia garantizada con Fruity.

Fuentes: [captura de reproducción en Android](https://developer.android.com/media/platform/av-capture), [EnvironmentalReverb](https://developer.android.com/reference/android/media/audiofx/EnvironmentalReverb) y [manual de Fruity Reeverb 2](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/Fruity%20Reeverb%202.htm).

La comprobación posterior de 1.4.1 con RVX confirmó señal continua, `originalMuted=true` y `muteError=null`. El usuario confirmó DRY habilitado. La sustitución del original y la mezcla completa ya funcionan en esta combinación de app y teléfono; su compatibilidad con otras fuentes o equipos requiere pruebas propias. Ver [mediciones del dispositivo](device-testing.md).
