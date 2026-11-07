# Audiowav para Windows x64

La versión 1.5.0 incorpora una aplicación de escritorio nativa para Windows 11 de 64 bits. Comparte Flutter y el motor de reverberación con Android, pero utiliza un backend de audio C++ específico de Windows. No necesita Java, ADB ni emulación Android para ejecutarse.

## Uso

Extrae **toda** la carpeta del ZIP y abre `audiowav.exe`. Conserva junto al ejecutable `flutter_windows.dll`, las DLL de runtime y la carpeta `data`.

- **Archivo local:** pulsa Abrir audio y selecciona un archivo compatible con Media Foundation. Incluye pausa, búsqueda y cola de reverb. El selector ofrece WAV, MP3, M4A, AAC, FLAC y WMA; la disponibilidad de decodificadores depende de Windows.
- **Otras aplicaciones:** reproduce audio, selecciona el proceso que aparece y pulsa Activar DSP. En navegadores puede aparecer el proceso auxiliar que mantiene la sesión de audio. Solo se captura el proceso seleccionado y sus descendientes, excluyendo Audiowav.
- El motor permite ecualizador de cinco bandas, graves, ganancia de hasta +12 dB, balance y los doce controles de Reverb Studio. El volumen de Windows cambia el volumen del dispositivo de salida predeterminado.
- Al controlar el original se habilita DRY. Si no se confirma el control, se mantiene únicamente un retorno WET y se informa en la interfaz. Detener y restaurar original termina la captura y devuelve la fuente a su estado anterior.

La captura se inicia únicamente por acción del usuario. No abre el micrófono, no guarda PCM y no envía audio. Añade retardo de captura y reproducción. Las aplicaciones con contenido protegido, salida exclusiva o políticas restrictivas pueden impedir que se reciba señal. No es un efecto APO instalado en el sistema ni modifica todas las aplicaciones automáticamente.

### Ruta completa mediante cable virtual

La lista de fuentes detecta salidas virtuales conocidas (VB-CABLE y compatibles) si están instaladas. El controlador se obtiene e instala por separado; no se incluye dentro de Audiowav ni se instala automáticamente. [VB-CABLE](https://vb-audio.com/Cable/) es software de terceros con su propia licencia, independiente de la licencia MIT de Audiowav.

1. En **Dispositivo de salida del DSP**, elige tus altavoces o auriculares físicos.
2. En el mezclador de volumen de Windows, envía la salida de la app de origen a **CABLE Input**. También puedes elegir esa salida directamente en una app que tenga su propio selector.
3. En Audiowav, selecciona **Cable virtual · CABLE Input** como fuente y pulsa Activar DSP.
4. El DSP recibe esa salida virtual y reproduce la mezcla completa por la salida física. La aplicación rechaza que fuente y salida sean el mismo dispositivo para evitar realimentación.
5. Al detener el DSP, devuelve la salida de la app a sus altavoces desde Windows para escucharla directamente. Audiowav no modifica automáticamente ese enrutamiento.

Los controles completos actúan sobre el audio que se envíe al cable. La captura directa por proceso conserva el retorno WET como alternativa sin controlador; su EQ y ganancia afectan al retorno, no sustituyen el sonido original cuando DRY está deshabilitado.

## Arquitectura

```text
Media Foundation Source Reader (archivo)
                  o
WASAPI process loopback (proceso elegido) / loopback de cable virtual aislado
                  ↓
PCM estéreo 48 kHz → EQ y graves → Reverb C++ compartida
                  → ganancia y balance suavizados → limitador → WASAPI
```

La captura por proceso usa `ActivateAudioInterfaceAsync` y `AUDIOCLIENT_ACTIVATION_PARAMS`. El origen se identifica por PID a partir de sesiones activas de Core Audio. No se captura la mezcla del dispositivo físico de salida, lo que evita recapturar el retorno de Audiowav. La ruta de cable captura únicamente su endpoint virtual y exige una salida diferente. La ruta de archivos pide a Media Foundation PCM flotante estéreo a 48 kHz y verifica el formato que recibe.

El hilo de audio posee las interfaces COM, decodificador, captura, salida y DSP. Flutter envía cambios de parámetros; el hilo los toma entre bloques. La cola de captura es acotada para limitar el crecimiento de retardo después de una interrupción. La reverb usa una red de ocho retardos, primeras reflexiones, filtros y difusión. El ecualizador y los graves usan filtros biquad; la ganancia y el balance se suavizan. Un limitador estéreo limita los picos, sin aumentar la potencia física de los altavoces.

Para sustituir el original se usa `ISimpleAudioVolume` únicamente en las sesiones del proceso elegido que estaban sin silenciar. Se verifica el estado y que la captura siga recibiendo señal. Al detener, fallar o cerrar, se restauran esas sesiones. Un proceso auxiliar oculto espera al cierre inesperado de Audiowav y restaura las sesiones registradas; no captura audio. Las sesiones que ya estaban silenciadas no se modifican. No se cambian el volumen de origen ni el dispositivo predeterminado.

Los ajustes y presets se guardan en `%LOCALAPPDATA%\Audiowav\settings.bin`. Al abrir la aplicación el motor empieza apagado; no se reanuda una captura automáticamente. Si se desconecta la salida, se informa el error y se debe volver a activar la ruta.

## Compilar

Requisitos: Flutter compatible con `pubspec.yaml`, Visual Studio Build Tools 2022 con herramientas C++ x64, CMake y Windows SDK 10.0.26100 o posterior.

```powershell
flutter pub get
flutter build windows --release
```

Salida: `build/windows/x64/runner/Release/`. Se distribuye la carpeta completa, no únicamente el EXE.

Para generar la carpeta portable y su ZIP con el runtime C++ y SHA-256: `powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1`. Si ya compilaste la versión actual, agrega `-SkipBuild`. Los paquetes se guardan en `dist/`. La compilación de pruebas no tiene firma Authenticode.

## Comprobar

```powershell
flutter analyze
flutter test
cmake -S native_tests -B build/native-windows -A x64
cmake --build build/native-windows --config Release
ctest --test-dir build/native-windows -C Release --output-on-failure
```

La aplicación incluye un modo de diagnóstico explícito:

```powershell
.\audiowav.exe --audio-self-test C:\ruta\resultado-audio.txt
```

Genera señales de prueba de nivel muy bajo y un archivo temporal propio. Comprueba decodificación mono a 44,1 kHz, conversión estéreo a 48 kHz, pausa, búsqueda y reanudación. Después crea un proceso propio con un tono de prueba, comprueba captura por proceso, continuidad con el original silenciado y restauración al detener. No selecciona ni captura el audio personal de otra aplicación. El informe registra resultados y contadores, no PCM.

Las pruebas de señales verifican la respuesta del ecualizador y de graves, ganancia, bypass, limitación, balance y ausencia de señal DRY en un retorno WET. Las pruebas de Flutter verifican la interfaz de escritorio en dos anchos y la selección explícita de la fuente.

Los contadores de fotogramas, ejecución máxima de un bloque e interrupciones no miden la latencia total ni demuestran equivalencia sonora con Fruity Reeverb 2.

## Comprobación del 7 de noviembre de 2026

En Windows 11 Home 24H2 (compilación 26100), Intel Core i5-10400T x64, la compilación Release pasó la prueba nativa: archivo mono a 44,1 kHz convertido a estéreo a 48 kHz, reproducción WASAPI, pausa, búsqueda en pausa y reanudación. La captura de un proceso propio con tono de prueba funcionó. En este equipo, silenciar su sesión también silenció la captura: el motor restauró el original y pasó al retorno WET. Se registraron 122.914 fotogramas, un bloque DSP máximo de 488 µs y cero interrupciones de salida. La prueba confirmó restauración del estado de mute al detener. No se capturó audio personal.

Pasaron las 25 pruebas Flutter, incluidas dos de escritorio, y las suites nativas de reverb y DSP de escritorio (18 comprobaciones de señal en total). El análisis de Dart no informó problemas. La interfaz Release se abrió y se revisó en esta PC. La ruta con cable virtual está implementada y requiere instalar y comprobar un controlador por separado; no se presenta como verificada antes de esa prueba.

Referencias de API: [captura por proceso](https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/applicationloopbackaudio-sample/), [Source Reader](https://learn.microsoft.com/en-us/windows/win32/medfound/source-reader), [ISimpleAudioVolume](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume).
