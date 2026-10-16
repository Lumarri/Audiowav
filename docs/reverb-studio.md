# Reverb Studio

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

DRY independiente, filtros H.CUT/L.CUT, modulación y velocidad, BASS/CROSS, MID/SIDE, separación estéreo y sincronización a tempo no están implementados sobre el audio de otras apps. La interfaz no los presenta como controles operativos. Igualar esas funciones requiere procesar directamente las muestras de audio con otro motor, una capacidad que este efecto nativo por sesión no proporciona.

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

En el reproductor propio se utiliza el mismo conjunto de parámetros con un efecto auxiliar conectado al `MediaPlayer`. En las otras apps se requiere una variante de inserción del dispositivo y una sesión detectable. Los ajustes anteriores se migran conservando el decaimiento de su ambiente y WET.
