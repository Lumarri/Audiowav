import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'audio_controller.dart';
import 'reverb_panel.dart';

const _lime = Color(0xFFB8F76A), _muted = Color(0xFF96A0AE);

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, this.controller});
  final AudioController? controller;
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final AudioController audio;
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
    final s = audio.settings;
    final canEdit = audio.supported && !audio.loading;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _lime,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Color(0xFF0C1015),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'audiowav',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            'TU SONIDO. A TU MANERA.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 9,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Acerca del audio',
                      onPressed: _showInfo,
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Text(
                  'Dale otra dimensión\na tu música.',
                  style: TextStyle(
                    fontSize: 33,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ajusta cada frecuencia. Encuentra tu equilibrio.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (!audio.supported)
                  _notice(
                    'Esta versión procesa audio en Android. El motor para iOS aún no está implementado.',
                  ),
                if (audio.error != null || audio.state['error'] != null)
                  _notice(audio.error ?? audio.state['error'].toString()),
                _panel(
                  Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.power_settings_new_rounded,
                            color: s.enabled ? _lime : _muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Motor de audio',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  audio.loading
                                      ? 'Conectando…'
                                      : audio.running
                                      ? (s.enabled
                                            ? (audio.sessions > 0 ||
                                                      audio.hasTrack
                                                  ? 'Efectos conectados'
                                                  : 'Esperando una sesión de audio')
                                            : 'Efectos en bypass')
                                      : 'Actívalo para comenzar',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: s.enabled,
                            onChanged: canEdit
                                ? (v) => audio.update((s) => s.enabled = v)
                                : null,
                          ),
                        ],
                      ),
                      if (audio.running) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Icon(
                              Icons.link_rounded,
                              size: 16,
                              color: _lime,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${audio.sessions} sesiones de otras apps · ${audio.hasTrack ? 'archivo conectado' : 'sin archivo'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: audio.stop,
                              child: const Text('Detener'),
                            ),
                          ],
                        ),
                      ],
                      if (audio.running &&
                          s.enabled &&
                          audio.sessions == 0 &&
                          !audio.hasTrack)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'No hay audio conectado: los controles se habilitan cuando se detecte una sesión.',
                            style: TextStyle(color: _muted, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _panel(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(Icons.tune_rounded, 'Ecualizador', '5 BANDAS'),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: equalizerPresets.keys
                              .map(
                                (name) => Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: ChoiceChip(
                                    label: Text(name),
                                    selected: s.preset == name,
                                    onSelected:
                                        canEdit && audio.available('equalizer')
                                        ? (_) => audio.selectPreset(name)
                                        : null,
                                    showCheckmark: false,
                                    selectedColor: _lime.withValues(alpha: .18),
                                    labelStyle: TextStyle(
                                      color: s.preset == name ? _lime : _muted,
                                      fontSize: 12,
                                    ),
                                    side: BorderSide(
                                      color: s.preset == name
                                          ? _lime.withValues(alpha: .5)
                                          : Colors.white12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 60,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _CurvePainter(s.bands, active: s.enabled),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${s.bands[i] > 0 ? '+' : ''}${s.bands[i].toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: _lime,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(
                                  height: 155,
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Slider(
                                      value: s.bands[i],
                                      min: -12,
                                      max: 12,
                                      divisions: 24,
                                      label: '${s.bands[i].round()} dB',
                                      onChanged:
                                          canEdit &&
                                              audio.available('equalizer')
                                          ? (v) => audio.update((s) {
                                              s.bands[i] = v;
                                              s.preset = 'Personalizado';
                                            })
                                          : null,
                                    ),
                                  ),
                                ),
                                Text(
                                  ['60', '230', '910', '3.6k', '14k'][i],
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'FRECUENCIA (Hz)  ·  −12 a +12 dB',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: _muted,
                          ),
                        ),
                      ),
                      if (canEdit && !audio.available('equalizer'))
                        _unavailable('Ecualizador'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _panel(ReverbPanel(audio: audio)),
                const SizedBox(height: 16),
                _panel(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(
                        Icons.speaker_rounded,
                        'Potencia y balance',
                        'SALIDA',
                      ),
                      const SizedBox(height: 20),
                      _control(
                        'Refuerzo de graves',
                        '${(s.bass * 100).round()}%',
                        s.bass,
                        0,
                        1,
                        canEdit && audio.available('bass')
                            ? (v) => audio.update((s) => s.bass = v)
                            : null,
                      ),
                      _control(
                        'Ganancia adicional',
                        '+${s.gain.toStringAsFixed(1)} dB',
                        s.gain,
                        0,
                        12,
                        canEdit && audio.available('gain')
                            ? (v) => audio.update((s) => s.gain = v)
                            : null,
                      ),
                      if (s.gain >= 6)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: Text(
                            'La ganancia alta puede distorsionar. Sube el nivel gradualmente.',
                            style: TextStyle(
                              color: Color(0xFFF1C878),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      _control(
                        'Balance estéreo',
                        s.balance.abs() < .02
                            ? 'Centro'
                            : '${s.balance < 0 ? 'Izq.' : 'Der.'} ${(s.balance.abs() * 100).round()}%',
                        s.balance,
                        -1,
                        1,
                        canEdit && audio.hasTrack
                            ? (v) => audio.update((s) => s.balance = v)
                            : null,
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('L', style: TextStyle(color: _muted)),
                          Text('R', style: TextStyle(color: _muted)),
                        ],
                      ),
                      const Divider(height: 28),
                      _control(
                        'Volumen multimedia del teléfono',
                        '${(audio.volume * 100).round()}%',
                        audio.volume.clamp(0, 1),
                        0,
                        1,
                        canEdit ? audio.setVolume : null,
                      ),
                      if (canEdit && !audio.available('bass'))
                        _unavailable('Refuerzo de graves'),
                      if (canEdit && !audio.available('gain'))
                        _unavailable('Ganancia'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _panel(
                  Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _lime.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: _lime,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  audio.track,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'REPRODUCTOR LOCAL',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 9,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: canEdit ? audio.openFile : null,
                            tooltip: 'Abrir archivo de audio',
                            icon: const Icon(Icons.folder_open_rounded),
                          ),
                        ],
                      ),
                      if (audio.hasTrack) ...[
                        Slider(
                          value: audio.position.toDouble().clamp(
                            0,
                            math.max(1, audio.duration).toDouble(),
                          ),
                          max: math.max(1, audio.duration).toDouble(),
                          onChanged: audio.duration > 0 ? audio.seek : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _time(audio.position),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                            IconButton.filled(
                              onPressed: audio.togglePlayback,
                              tooltip: audio.playing ? 'Pausar' : 'Reproducir',
                              icon: Icon(
                                audio.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            Text(
                              _time(audio.duration),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: canEdit ? audio.openFile : null,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Abrir una canción'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'OTRAS APPS',
                  style: TextStyle(
                    color: _lime,
                    letterSpacing: 1.7,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  audio.advancedDetection
                      ? 'Detección avanzada activada. Inicia la música en otra app: Audiowav conecta sus efectos automáticamente en unos segundos.'
                      : 'Activa el motor y después inicia la música en una app que comparta su sesión. Para detectar otras apps automáticamente, habilita la detección avanzada una vez desde una PC.',
                  style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
                ),
                if (audio.supported && !audio.advancedDetection) ...[
                  const SizedBox(height: 10),
                  const SelectableText(
                    'adb shell pm grant com.audiowav.audiowav android.permission.DUMP',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'El permiso permite leer diagnósticos del sistema para localizar sesiones de audio. No se graba sonido.',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
                if (audio.state['detectionError'] != null)
                  _notice(audio.state['detectionError'].toString()),
                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    'HECHO PARA ESCUCHAR LOS DETALLES',
                    style: TextStyle(
                      color: _muted,
                      letterSpacing: 1.8,
                      fontSize: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF171C23),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: _panel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFF1C878), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _heading(IconData icon, String title, String tag) => Row(
    children: [
      Icon(icon, color: _lime, size: 20),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      Text(
        tag,
        style: const TextStyle(color: _muted, fontSize: 8, letterSpacing: 1.3),
      ),
    ],
  );
  Widget _unavailable(String effect) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      '$effect no disponible en este dispositivo o sesión.',
      style: const TextStyle(color: _muted, fontSize: 11),
    ),
  );
  Widget _control(
    String label,
    String value,
    double current,
    double min,
    double max,
    ValueChanged<double>? onChanged,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            value,
            style: const TextStyle(
              color: _lime,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(value: current, min: min, max: max, onChanged: onChanged),
    ],
  );
  String _time(int ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
  void _showInfo() => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Un estudio en tu bolsillo',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Audiowav usa los efectos de Android. El ecualizador adapta sus 5 controles a las bandas del dispositivo.\n\nLa detección avanzada encuentra sesiones de otras apps con el permiso de diagnóstico DUMP, habilitado por USB. La reverberación externa depende de un efecto de inserción del fabricante; si Android no permite usarlo, se muestra como no disponible. El balance funciona con los archivos abiertos aquí.\n\nLa ganancia aumenta el nivel de la señal; la potencia máxima depende del equipo. Usa un volumen cómodo y evita la distorsión.',
              style: TextStyle(color: _muted, height: 1.6),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.bands, {required this.active});
  final List<double> bands;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = i * size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = List.generate(
      5,
      (i) => Offset(
        size.width * (i + .5) / 5,
        size.height / 2 - bands[i] / 12 * size.height * .42,
      ),
    );
    final line = Path()
      ..moveTo(0, points.first.dy)
      ..lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    line.lineTo(size.width, points.last.dy);
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _lime.withValues(alpha: active ? .2 : .06),
            _lime.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = active ? _lime : _muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
