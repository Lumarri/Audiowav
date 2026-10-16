# Pruebas en Android

Usar un teléfono físico y auriculares estéreo. Comenzar con volumen bajo. Un emulador sirve para verificar navegación y servicio, pero no representa los efectos disponibles en cada teléfono.

1. Abrir Audiowav después de una instalación limpia. No debe iniciar el servicio automáticamente.
2. Activar el motor y conceder notificaciones si Android lo solicita. Verificar la notificación persistente y el botón Detener.
3. Abrir un archivo estéreo WAV, MP3 o AAC desde el selector. Cancelar el selector debe devolver a la app sin error. Probar también un archivo inválido: debe mostrar un mensaje y permitir abrir otro.
4. Verificar reproducción/pausa, búsqueda, duración y reproducción con pantalla apagada. Probar los botones de la notificación.
5. Cambiar presets y bandas. Comparar motor activado/desactivado con la misma canción. Los controles de bandas deben responder también en dispositivos con diferente número de bandas.
6. Ajustar graves y ganancia gradualmente. Los efectos ausentes o sin control deben aparecer deshabilitados.
7. Probar todos los ambientes de reverb y su mezcla con audio local. Comprobar balance izquierdo, centro y derecho con un archivo estéreo conocido.
8. Cambiar volumen y comprobar que cambia el volumen multimedia de Android. No debe modificar el volumen de llamadas.
9. Desconectar auriculares: la reproducción local debe pausarse. Iniciar otra app que tome el foco de audio: Audiowav debe pausar o atenuar según la solicitud y respetar la pérdida permanente de foco.
10. Con el motor activo, iniciar reproducción en una app que anuncie `OPEN_AUDIO_EFFECT_CONTROL_SESSION`. Verificar que sube el contador y que ecualizador/graves/ganancia responden. Al cerrar esa sesión debe bajar. Una app que no anuncie sesiones no es compatible.
11. Salir y volver a abrir la interfaz mientras se reproduce: debe reconectarse al servicio. Detener desde la notificación: debe liberar audio y efectos. Abrir de nuevo no debe reiniciar el servicio por sí solo.
12. Reiniciar la app y comprobar la persistencia de presets, bandas, graves, ganancia, balance y reverb. El volumen no se eleva automáticamente al iniciar.

Registrar modelo, versión Android, ruta de salida y efectos disponibles. El soporte de sesiones externas y de reverb debe validarse por dispositivo.
