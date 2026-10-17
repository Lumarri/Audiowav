import 'package:flutter/material.dart';

import 'audio_controller.dart';

class CaptureProbePanel extends StatefulWidget {
  const CaptureProbePanel({super.key, required this.audio});
  final AudioController audio;

  @override
  State<CaptureProbePanel> createState() => _CaptureProbePanelState();
}

class _CaptureProbePanelState extends State<CaptureProbePanel> {
  String? target;

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    if (!audio.supported || audio.state['captureSupported'] != true) {
      return const SizedBox.shrink();
    }
    final targets = audio.captureTargets;
    final ids = targets.map((item) => item['id'] as String).toList();
    final selected = ids.contains(target)
        ? target
        : ids.contains('app.rvx.android.apps.youtube.music')
        ? 'app.rvx.android.apps.youtube.music'
        : ids.firstOrNull;
    final busy = audio.captureActive || audio.probePending;
    final probe = audio.captureProbe;
    final elapsed = (probe['elapsedMs'] as num? ?? 0).toDouble();
    final signal = probe['signalDetected'] == true;
    final status = probe['status'] as String? ?? 'idle';
    final processing = probe['mode'] == 'dsp';
    final message = processing && status == 'running'
        ? (audio.externalDspActive
              ? (audio.externalDryControl
                    ? 'Reverb Studio en vivo: mezcla DRY/WET disponible.'
                    : 'Reverb Studio en vivo: retorno WET. No se confirmó el control del original.')
              : 'Conectando Reverb Studio. Mantén una canción reproduciéndose en la app elegida.')
        : switch (status) {
            'running' =>
              signal
                  ? 'Está llegando audio de ${probe['label'] ?? 'la app elegida'}.'
                  : 'Escuchando la señal interna. Mantén una canción reproduciéndose.',
            'signal' =>
              'Se recibió audio de ${probe['label']}. Podemos evaluar el DSP externo con esta app.',
            'no_signal' => 'No se confirmó señal. Comprueba que la app elegida estaba reproduciendo una canción. Si vuelve a fallar, puede estar bloqueando la captura.',
            'revoked' => 'Android retiró la autorización. La prueba se detuvo.',
            'stopped' =>
              processing
                  ? 'DSP en vivo detenido. Se restauró el sonido original.'
                  : signal
                  ? 'Prueba detenida. Se recibió señal de ${probe['label']}.'
                  : 'Prueba detenida sin confirmar señal.',
            'error' =>
              probe['error'] as String? ?? 'No se pudo completar la prueba.',
            _ => 'Primero verificaremos si podemos recibir el audio de tu app.',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audio de otras apps · DSP',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reproduce una canción y vuelve aquí. La prueba mide durante 20 segundos solo el audio interno de la app elegida. No guarda ni envía audio y no captura imágenes ni el micrófono.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 12),
              if (targets.isEmpty)
                const Text(
                  'No se encontró YouTube Music, Spotify ni Deezer instalados para este usuario.',
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'App que está reproduciendo música',
                  ),
                  isExpanded: true,
                  items: targets
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'] as String,
                          child: Text(item['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) => setState(() => target = value),
                ),
              const SizedBox(height: 12),
              Text(
                audio.probePending
                    ? 'Esperando autorización de Android…'
                    : audio.error ?? message,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              if (status != 'idle' && !audio.probePending) ...[
                const SizedBox(height: 8),
                if (!processing)
                  LinearProgressIndicator(value: (elapsed / 20000).clamp(0, 1)),
                const SizedBox(height: 6),
                Text(
                  '${(elapsed / 1000).floor()} ${processing ? 's · DSP' : '/ 20 s'} · Pico: ${(probe['peakDb'] as num? ?? -120).toStringAsFixed(1)} dBFS',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              if (audio.captureActive)
                OutlinedButton.icon(
                  onPressed: audio.stopCaptureProbe,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(
                    processing ? 'Detener DSP en vivo' : 'Detener prueba',
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: busy || selected == null
                      ? null
                      : () => audio.startCaptureProbe(selected),
                  icon: const Icon(Icons.hearing_rounded),
                  label: const Text('Probar 20 segundos'),
                ),
              if (!audio.captureActive)
                OutlinedButton.icon(
                  onPressed: busy || selected == null
                      ? null
                      : () => audio.startExternalDsp(selected),
                  icon: const Icon(Icons.surround_sound_rounded),
                  label: const Text('Activar Reverb Studio en vivo'),
                ),
              if (probe['muteError'] != null)
                Text(
                  probe['muteError'].toString(),
                  style: const TextStyle(fontSize: 11),
                ),
              const SizedBox(height: 8),
              const Text(
                'Android pedirá autorización para cada inicio. Probar mide señal durante 20 segundos. Reverb Studio en vivo procesa y reproduce el audio hasta pulsar Detener; añade retardo y no guarda audio ni imágenes.',
                style: TextStyle(fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
