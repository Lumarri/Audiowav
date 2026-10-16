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

## Comprobación realizada el 16 de octubre de 2026

En un Moto g24 power con Android 14 se verificó la conexión automática a la sesión de RVX Music mediante DUMP. Sin archivo local abierto, los diagnósticos del motor devolvieron simultáneamente control de ecualizador, graves, ganancia y reverb. Lecturas reales de los efectos: bandas `[400, 200, 200, 400, 900]` mB, graves 469/1000, ganancia activada a 582 mB y reverb activada con decaimiento de 1400 ms. Los valores coincidieron con los ajustes de la interfaz. Esta comprobación valida la conexión y los parámetros del motor; la percepción audible requiere escuchar el equipo.

Consultar los valores aplicados, sin capturar audio:

```sh
adb shell dumpsys activity service com.audiowav.audiowav/.AudioService
```

Si se reinstala la app mientras otra app mantiene una sesión abierta, Android puede conservar temporalmente motores sin cliente y rechazar una conexión nueva. Reiniciar la reproducción/app de música una vez libera esa sesión. Los ajustes posteriores se aplican en vivo sin reiniciar.
