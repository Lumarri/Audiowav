import 'package:flutter/material.dart';

import 'audio_controller.dart';
import 'reverb_panel.dart';

const _accent = Color(0xFFB8F76A);
const _muted = Color(0xFF96A0AE);

class DesktopStudioScreen extends StatefulWidget {
  const DesktopStudioScreen({super.key, this.controller});
  final AudioController? controller;
  @override
  State<DesktopStudioScreen> createState() => _DesktopStudioScreenState();
}

class _DesktopStudioScreenState extends State<DesktopStudioScreen> {
  late final AudioController audio;
  String? target;
  @override
  void initState() {
    super.initState();
    audio = widget.controller ?? AudioController();
    audio.addListener(_changed);
    audio.initialize();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audio.removeListener(_changed);
    if (widget.controller == null) audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = audio.settings;
    final editable = !audio.loading && audio.supported;
    final targets = audio.captureTargets;
    final selected = targets.any((app) => app['id'] == target)
        ? target
        : targets.firstOrNull?['id'] as String?;
    final cable =
        (selected?.startsWith('cable:') ?? false) ||
        (audio.captureProbe['label'] as String? ?? '').startsWith(
          'Cable virtual',
        );
    final outputs = (audio.state['outputDevices'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final outputId = audio.state['selectedOutput'] as String? ?? '';
    final source = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.input_rounded, 'Fuente de audio'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Archivo local'),
                selected: audio.localReverbView,
                onSelected: (_) => audio.selectReverbSource(true),
              ),
              ChoiceChip(
                label: const Text('Otras aplicaciones'),
                selected: !audio.localReverbView,
                onSelected: (_) => audio.selectReverbSource(false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (audio.localReverbView) ...[
            Text(
              audio.track,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: editable ? audio.openFile : null,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Abrir audio'),
            ),
            if (audio.hasTrack) ...[
              const SizedBox(height: 12),
              Slider(
                value: audio.position.toDouble().clamp(
                  0,
                  audio.duration.toDouble().clamp(1, double.infinity),
                ),
                min: 0,
                max: audio.duration.toDouble().clamp(1, double.infinity),
                onChanged: audio.duration > 0 ? audio.seek : null,
              ),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: audio.togglePlayback,
                    icon: Icon(
                      audio.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_time(audio.position)} / ${_time(audio.duration)}',
                    style: const TextStyle(color: _muted),
                  ),
                  if (audio.state['tail'] == true)
                    const Expanded(
                      child: Text(
                        ' · Cola de reverb',
                        style: TextStyle(color: _accent),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Decodificación de Windows → DSP C++ → salida WASAPI estéreo a 48 kHz.',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Aplicación con audio activo',
              ),
              items: targets
                  .map(
                    (app) => DropdownMenuItem<String>(
                      value: app['id'] as String,
                      child: Text(
                        app['label'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: audio.captureActive
                  ? null
                  : (value) => setState(() => target = value),
            ),
            const SizedBox(height: 12),
            if (audio.captureActive)
              OutlinedButton.icon(
                onPressed: audio.stopCaptureProbe,
                icon: const Icon(Icons.stop_rounded),
                label: Text(
                  cable ? 'Detener DSP' : 'Detener y restaurar original',
                ),
              )
            else
              FilledButton.icon(
                onPressed: !editable || selected == null || audio.probePending
                    ? null
                    : () => audio.startExternalDsp(selected),
                icon: const Icon(Icons.surround_sound_rounded),
                label: Text(audio.probePending ? 'Conectando…' : 'Activar DSP'),
              ),
            const SizedBox(height: 12),
            Text(
              audio.externalDspActive
                  ? audio.externalDryControl
                        ? cable
                              ? 'En vivo · Cable virtual · Mezcla DRY/WET completa.'
                              : 'En vivo · Mezcla DRY/WET completa. El original se restaura al detener.'
                        : 'En vivo · Retorno WET. No se pudo controlar el original.'
                  : targets.isEmpty
                  ? 'Reproduce música en el navegador, un reproductor o un juego para que aparezca aquí.'
                  : 'Captura solo el proceso elegido y sus hijos. Añade retardo; no se graba audio ni se usa el micrófono.',
              style: const TextStyle(fontSize: 12, color: _muted, height: 1.5),
            ),
            if (audio.captureProbe['muteError'] != null)
              Text(
                audio.captureProbe['muteError'].toString(),
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            const SizedBox(height: 12),
            Text(
              cable
                  ? 'En Windows, envía la salida de la app al cable virtual y elige aquí tus altavoces como salida. Al detener el DSP, devuelve la app a sus altavoces desde el mezclador de Windows.'
                  : 'Para EQ y mezcla completa de otras apps, puedes usar un cable virtual como fuente. La captura directa puede quedar limitada al retorno de reverb si Windows silencia también la captura.',
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
    final equalizer = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.graphic_eq_rounded, 'Ecualizador · 5 bandas'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: equalizerPresets.keys
                .map(
                  (name) => ChoiceChip(
                    label: Text(name),
                    selected: settings.preset == name,
                    onSelected: editable
                        ? (_) => audio.selectPreset(name)
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 5; i++)
            _slider(
              const ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'][i],
              '${settings.bands[i] >= 0 ? '+' : ''}${settings.bands[i].toStringAsFixed(1)} dB',
              settings.bands[i],
              -12,
              12,
              editable
                  ? (value) => audio.update((s) {
                      s.bands[i] = value;
                      s.preset = 'Personalizado';
                    })
                  : null,
            ),
        ],
      ),
    );
    final output = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.speaker_rounded, 'Salida y dinámica'),
          const SizedBox(height: 16),
          if (outputs.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('output:$outputId'),
              initialValue: outputs.any((item) => item['id'] == outputId)
                  ? outputId
                  : '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Dispositivo de salida del DSP',
              ),
              items: outputs
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item['id'] as String,
                      child: Text(
                        item['label'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: editable
                  ? (id) {
                      if (id != null) audio.selectOutput(id);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Cambiar la salida detiene la reproducción. Para un cable virtual, elige una salida física diferente.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 16),
          ],
          _slider(
            'Refuerzo de graves',
            '${(settings.bass * 100).round()}%',
            settings.bass,
            0,
            1,
            editable ? (v) => audio.update((s) => s.bass = v) : null,
          ),
          _slider(
            'Ganancia',
            '+${settings.gain.toStringAsFixed(1)} dB',
            settings.gain,
            0,
            12,
            editable ? (v) => audio.update((s) => s.gain = v) : null,
          ),
          _slider(
            'Balance',
            settings.balance.abs() < .02
                ? 'Centro'
                : settings.balance < 0
                ? 'Izquierda'
                : 'Derecha',
            settings.balance,
            -1,
            1,
            editable ? (v) => audio.update((s) => s.balance = v) : null,
          ),
          _slider(
            'Volumen de Windows',
            '${(audio.volume * 100).round()}%',
            audio.volume.clamp(0, 1),
            0,
            1,
            editable ? audio.setVolume : null,
          ),
          const Text(
            'Limitador estéreo para controlar picos. La ganancia no aumenta la potencia física del equipo.',
            style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
          ),
          if (audio.state['outputDevice'] case final String device
              when device.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(device, style: const TextStyle(color: _accent, fontSize: 12)),
          ],
        ],
      ),
    );
    final reverb = _card(ReverbPanel(audio: audio));
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            color: _accent,
                            size: 36,
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'audiowav',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                  ),
                                ),
                                Text(
                                  'ESTUDIO PARA WINDOWS · x64',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            settings.enabled ? 'DSP activo' : 'Bypass',
                            style: const TextStyle(color: _accent),
                          ),
                          Switch(
                            value: settings.enabled,
                            onChanged: editable
                                ? (v) => audio.update((s) => s.enabled = v)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (audio.error != null ||
                          audio.state['error'] != null) ...[
                        _card(
                          Text(
                            audio.error ?? audio.state['error'].toString(),
                            style: const TextStyle(color: Colors.amber),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (bounds.maxWidth >= 1050)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  source,
                                  const SizedBox(height: 16),
                                  equalizer,
                                  const SizedBox(height: 16),
                                  output,
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(flex: 6, child: reverb),
                          ],
                        )
                      else
                        Column(
                          children: [
                            source,
                            const SizedBox(height: 16),
                            equalizer,
                            const SizedBox(height: 16),
                            reverb,
                            const SizedBox(height: 16),
                            output,
                          ],
                        ),
                      const SizedBox(height: 20),
                      Text(
                        '${audio.running ? 'Motor en ejecución' : 'Motor detenido'} · '
                        '${audio.state['processedFrames'] ?? 0} fotogramas · '
                        'Bloque DSP máx.: ${audio.state['maxProcessMicros'] ?? 0} µs · '
                        'Interrupciones de salida: ${audio.state['underruns'] ?? 0}',
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'MIT · DSP propio. No utiliza el algoritmo propietario de Fruity Reeverb 2.',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF171C23),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _title(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: _accent, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
      ),
    ],
  );
  Widget _slider(
    String label,
    String value,
    double current,
    double min,
    double max,
    ValueChanged<double>? change,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(color: _accent)),
        ],
      ),
      Slider(value: current, min: min, max: max, onChanged: change),
    ],
  );
  String _time(int ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
}
