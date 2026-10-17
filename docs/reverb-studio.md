# Reverb Studio

## DSP en vivo para otras apps (1.4.0, experimental)

El botón **Activar DSP** solicita una captura nueva de la app indicada y conecta los bloques al mismo motor C++ que procesa archivos locales. La prueba de 20 segundos de 1.3.0 sigue siendo independiente. Después de confirmar señal y salida, PRE DEL, SIZE, los filtros, reflexiones, difusión, tono, anchura y WET actúan sobre el DSP propio en tiempo real; DEC admite hasta 20 s.

DRY requiere además controlar el original. Se filtran las sesiones de AudioFlinger por PID y UID del origen elegido, se intenta atenuar únicamente esas sesiones y se verifica control y ganancia con `DynamicsProcessing`. Si no hay confirmación, se usa un retorno WET y se mantiene DRY deshabilitado. Si la captura deja de entregar señal al controlar el original, se libera esa atenuación y se vuelve al retorno. Detener, desactivar el motor, abrir un archivo local o perder la proyección restaura la fuente. No se guarda audio y la salida propia no se puede recapturar.

No se promete latencia ni sustitución del original en todos los dispositivos. La confirmación del permiso de Android debe hacerla el usuario. Referencias de las API públicas: [captura interna](https://developer.android.com/media/platform/av-capture), [DynamicsProcessing](https://developer.android.com/reference/android/media/audiofx/DynamicsProcessing).

## Selección de fuente en la versión 1.2.1

El panel permite elegir **Archivo local** u **Otras apps** para consultar los controles de cada motor, incluso con un archivo local cargado y pausado. Los doce controles permanecen visibles; los que la fuente no admite quedan deshabilitados. La selección cambia la vista de disponibilidad; los ajustes compatibles se comparten entre ambos motores.

La vista inicial prioriza la reproducción local si está sonando; si está pausada y se detecta reproducción externa, muestra el motor Android. Una selección explícita permanece fija mientras la pantalla sigue abierta. El estado distingue bypass, reverb apagada, WET en cero, archivo pausado y ausencia de reproducción externa detectada. Las capacidades de otras apps priorizan las sesiones activas frente a anuncios antiguos.

El límite Android de DEC se aplica al enviar al efecto y al editar su perilla. Consultar ese límite no sobrescribe el valor de un preset del DSP propio que tenga una cola más larga. En este teléfono, los diagnósticos confirman un máximo nativo de 7 s y no confirman LATE DEL, ER ni ER DEL. Estos límites describen la ruta nativa; el DSP en vivo de 1.4.0 habilita filtros, anchura y reflexiones sobre la captura autorizada de YouTube Music.

## DSP local en la versión 1.2.0

Los archivos abiertos dentro de Audiowav usan un motor C++ propio. La ruta es `MediaExtractor` → `MediaCodec` (o PCM directo) → DSP → `AudioTrack`. No se carga el archivo completo en memoria. El código de procesamiento no hace asignaciones de memoria ni llamadas a Flutter durante cada bloque.

El motor incluye filtros de entrada de graves y agudos, predelay, primeras reflexiones, difusores allpass y una red de ocho retardos con matriz de Hadamard normalizada. El decaimiento controla la ganancia de realimentación según la longitud de cada retardo; una transición alrededor de 4 kHz modifica el decaimiento relativo de agudos. Los parámetros se interpolan entre bloques para reducir saltos durante los ajustes. Los niveles de salida se limitan a ±1; una mezcla alta puede recortar la señal.

Al abrir un archivo, el panel indica **DSP propio · Archivo local** y habilita:

| Control adicional o adaptado | Función local |
| --- | --- |
| PRE DEL | Retardo antes de la reverberación, incluidas las primeras reflexiones, de 0 a 100 ms |
| SIZE | Longitudes de las líneas de retardo de la cola |
| DEC | Decaimiento ajustable de 0,1 a 20 segundos; no aplica el límite del efecto del fabricante |
| L.CUT | Filtro de graves en la entrada del efecto, 20–2000 Hz |
| H.CUT | Filtro de agudos en la entrada del efecto, 2–20 kHz; limitado internamente según el muestreo |
| DRY | Nivel independiente de la señal original, 0–100% |
| WIDTH | Anchura del retorno, desde mono a estéreo ampliado, 0–200% |

WET, reflexiones, difusión, tono y amortiguación también actúan sobre el motor propio. Los filtros son de primer orden. Los presets existentes conservan su funcionamiento y reciben valores por defecto para los controles nuevos; los presets personales guardan todos los controles.

Pausar detiene también la cola; reanudar continúa la reproducción. Al buscar otra posición se vacían la cola, la salida pendiente y el estado del decodificador. Al terminar el archivo se procesa silencio hasta que la cola sea suficientemente baja, con un máximo de 22 segundos, y se espera a que la salida pendiente termine. Reproducir de nuevo tras el final vuelve al inicio.

El ecualizador, los graves y la ganancia siguen usando los efectos Android sobre la sesión de la salida local. Sin captura en vivo, otras apps usan el motor nativo descrito abajo. Con captura autorizada y señal confirmada, los controles del DSP propio también procesan otras apps; DRY requiere controlar el original.

Este es un algoritmo propio; no se promete equivalencia con Fruity Reeverb 2. La cifra de 40 ms del canal de controles no mide la latencia de audio. Las pruebas de señales del DSP se encuentran en `native_tests`; las pruebas de decodificación y reproducción reales están en `android/app/src/androidTest`.

## Motor Android para otras apps (desde 1.1.0)

La versión 1.1.0 amplía la reverberación para escuchar otras apps, como YouTube Music, manteniendo el motor nativo Android. Es una implementación propia de controles de estudio; no contiene ni reproduce el algoritmo de Fruity Reeverb 2 y no garantiza su sonido o eficiencia.

Referencia funcional consultada: [manual de Fruity Reeverb 2](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/Fruity%20Reeverb%202.htm). Los rangos y la aplicación en Android siguen [EnvironmentalReverb](https://developer.android.com/reference/android/media/audiofx/EnvironmentalReverb).

## Controles reales

| Control Audiowav | Qué modifica | Rango |
| --- | --- | --- |
| DEC | Duración de caída de la cola | 0,1–20 s |
| LATE DEL | Tiempo entre primeras reflexiones y cola | 0–100 ms |
| DENSITY | Densidad modal del efecto; no es el SIZE de Fruity | 0–100% |
| DIFF | Difusión de la cola | 0–100% |
| DAMP | Tiempo relativo de caída de las frecuencias altas | 0,1–2× |
| HF TONE | Atenuación de agudos del efecto a 5 kHz | −90–0 dB |
| ER | Nivel de las primeras reflexiones | 0–100% |
| ER DEL | Retraso antes de las primeras reflexiones | 0–300 ms |
| WET | Nivel del retorno de reverberación | 0–100% |

Los valores escritos se leen de vuelta del motor. Los controles cuyos parámetros no coincidan dentro de la tolerancia se deshabilitan, ya que algunos fabricantes aceptan ajustes que luego ignoran. La lectura correcta confirma el parámetro recibido por el motor; no constituye una medición acústica de su respuesta.

El decaimiento se adapta al límite observado del motor en vez de deshabilitarse cuando este recorta una petición larga. En el Moto g24 power con Android 14 se confirmó un máximo de **7 segundos**, aunque la API general admite hasta 20. Este teléfono devuelve cero para LATE DEL, ER y ER DEL; aparecen deshabilitados. Densidad, difusión, amortiguación, tono y WET se leen correctamente.

La calibración del máximo se conserva por implementación de efecto y versión del sistema. En la comprobación del 16 de octubre de 2026 se leyó una sesión externa con 7000 ms de caída, densidad 1000, difusión 950, relación HF 2000, tono HF −700 mB y retorno −912 mB. Ecualizador, graves y ganancia continuaron activos simultáneamente. `propertyWrites` permaneció en 1 al cambiar las bandas del ecualizador, confirmando que ese cambio no volvió a escribir la reverb.

El efecto nativo por sesión no proporciona DRY independiente, filtros H.CUT/L.CUT ni anchura. Esas funciones pertenecen al DSP propio descrito arriba; DRY en captura requiere controlar el original. Modulación y velocidad, BASS/CROSS, MID/SIDE y sincronización a tempo no están implementados en ninguno de los motores.

## Manejo

- Arrastrar una perilla hacia arriba/abajo para ajustar en vivo.
- Tocar el valor para introducir un número preciso.
- Doble toque en una perilla para restablecer su valor por defecto.
- Elegir Room, Hall, Plate, Vocal, Ambient o Cathedral como punto de partida. Son presets propios.
- Guardar hasta 16 presets personales, que incluyen parámetros y WET. Guardar el mismo nombre actualiza ese preset.
- El interruptor de reverb permite comparar con bypass sin modificar los demás efectos.

La gráfica es una envolvente estimada de caída, no una visualización del audio capturado. No se graba sonido.

## Eficiencia y comprobación

El motor se mantiene durante la sesión. La detección avanzada omite las pistas en pausa para no reservar efectos en apps que no estén reproduciendo. Los parámetros modificados se envían en un bloque y los ajustes idénticos se omiten; modificar la reverb tampoco vuelve a escribir los parámetros del ecualizador, graves o ganancia que no han cambiado. Los controles se comunican durante el arrastre a intervalos de 40 ms más el tiempo de la llamada nativa. Esto no es una medición de la latencia de audio ni una comparación de CPU con Fruity Reeverb 2.

Los diagnósticos incluyen los valores reales y `propertyWrites`, el número de bloques de parámetros escritos:

```sh
adb shell dumpsys activity service com.audiowav.audiowav/.AudioService
```

Hasta la versión 1.1.0, el reproductor propio utilizaba un efecto auxiliar conectado al `MediaPlayer`. En 1.2.0 lo sustituye el DSP local descrito arriba. Desde 1.4.0, otras apps pueden usar captura autorizada y DSP propio. La alternativa nativa sigue requiriendo una variante de inserción del dispositivo y una sesión detectable. Los ajustes anteriores se migran conservando el decaimiento de su ambiente y WET.
