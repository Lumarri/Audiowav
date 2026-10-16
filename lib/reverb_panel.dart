import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'audio_controller.dart';
import 'reverb_settings.dart';

const _accent = Color(0xFFB8F76A), _muted = Color(0xFF96A0AE);

class ReverbPanel extends StatelessWidget {
  const ReverbPanel({super.key, required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final s = audio.settings;
    final p = s.reverbParams;
    final available = audio.available('reverb');
    final active = available && s.reverb != 0;
    final profiles = <String, ReverbPreset>{
      for (final preset in reverbPresets) preset.name: preset,
      for (final preset in s.reverbUserPresets) 'user:${preset.name}': preset,
    };
    final selected = profiles.containsKey(s.reverbProfile)
        ? s.reverbProfile
        : 'Personalizado';
    void edit(void Function(ReverbParameters) change) =>
        audio.editReverb((s) => change(s.reverbParams));
    bool supports(String key) => active && audio.reverbControlAvailable(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.surround_sound_rounded, color: _accent, size: 22),
            const SizedBox(width: 9),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reverb Studio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'ESPACIO · TEXTURA · COLA',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 8,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: s.reverb != 0,
              onChanged: available
                  ? (v) => audio.update((s) => s.reverb = v ? 3 : 0)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Preset',
                  filled: true,
                  fillColor: Colors.black12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'Personalizado',
                    child: Text('Personalizado'),
                  ),
                  for (final item in profiles.entries)
                    DropdownMenuItem(
                      value: item.key,
                      child: Text(
                        '${item.key.startsWith('user:') ? '★ ' : ''}${item.value.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: available
                    ? (key) {
                        if (key != null && profiles[key] != null) {
                          audio.selectReverbPreset(
                            profiles[key]!,
                            userPreset: key.startsWith('user:'),
                          );
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Guardar preset de reverb',
              onPressed: audio.supported ? () => _save(context) : null,
              icon: const Icon(Icons.bookmark_add_outlined, color: _accent),
            ),
            if (selected.startsWith('user:'))
              IconButton(
                tooltip: 'Eliminar preset guardado',
                onPressed: () =>
                    audio.deleteReverbPreset(selected.substring(5)),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          height: 100,
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF10151B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ENVOLVENTE ESTIMADA',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 8,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  Text(
                    '${p.decay.toStringAsFixed(2)} s',
                    style: const TextStyle(color: _accent, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 60),
                  painter: _Envelope(
                    p.decay,
                    p.preDelay,
                    s.wet,
                    s.enabled && active,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final count = box.maxWidth >= 500 ? 4 : 3;
            final width = (box.maxWidth - 12 * (count - 1)) / count;
            Widget dial(
              String key,
              String title,
              String description,
              double value,
              double min,
              double max,
              double reset,
              String Function(double) format,
              void Function(double) change, {
              bool log = false,
            }) => SizedBox(
              width: width,
              child: ReverbDial(
                label: title,
                description: description,
                value: value,
                min: min,
                max: max,
                reset: reset,
                format: format,
                logarithmic: log,
                onChanged: supports(key) ? change : null,
                unsupported: available && !audio.reverbControlAvailable(key),
              ),
            );
            return Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                dial(
                  'decay',
                  'DEC',
                  'Decaimiento de la cola hasta −60 dB',
                  p.decay.clamp(.1, audio.maxReverbDecay),
                  .1,
                  audio.maxReverbDecay,
                  1.4,
                  (v) => '${v.toStringAsFixed(2)} s',
                  (v) => edit((p) => p.decay = v),
                  log: true,
                ),
                dial(
                  'preDelay',
                  'LATE DEL',
                  'Retraso de la cola respecto a las primeras reflexiones. Máximo Android: 100 ms.',
                  p.preDelay,
                  0,
                  100,
                  10,
                  (v) => '${v.round()} ms',
                  (v) => edit((p) => p.preDelay = v),
                ),
                dial(
                  'size',
                  'DENSITY',
                  'Densidad modal del espacio. No equivale al tamaño físico de Fruity Reeverb 2.',
                  p.size,
                  0,
                  100,
                  85,
                  (v) => '${v.round()}%',
                  (v) => edit((p) => p.size = v),
                ),
                dial(
                  'diffusion',
                  'DIFF',
                  'Difusión: de ecos separados a una cola más densa',
                  p.diffusion,
                  0,
                  100,
                  100,
                  (v) => '${v.round()}%',
                  (v) => edit((p) => p.diffusion = v),
                ),
                dial(
                  'hfRatio',
                  'DAMP',
                  'Tiempo de caída de los agudos respecto al resto. Menor que 1: cola más cálida.',
                  p.hfRatio,
                  .1,
                  2,
                  .8,
                  (v) => '${v.toStringAsFixed(2)}×',
                  (v) => edit((p) => p.hfRatio = v),
                ),
                dial(
                  'hfLevel',
                  'HF TONE',
                  'Atenuación de agudos de la reverb a 5 kHz',
                  p.hfLevel,
                  -90,
                  0,
                  -6,
                  (v) => '${v.toStringAsFixed(1)} dB',
                  (v) => edit((p) => p.hfLevel = v),
                ),
                dial(
                  'earlyLevel',
                  'ER',
                  'Nivel de las primeras reflexiones',
                  p.earlyLevel,
                  0,
                  1,
                  .25,
                  (v) => '${(v * 100).round()}%',
                  (v) => edit((p) => p.earlyLevel = v),
                ),
                dial(
                  'earlyDelay',
                  'ER DEL',
                  'Tiempo antes de las primeras reflexiones. Máximo Android: 300 ms.',
                  p.earlyDelay,
                  0,
                  300,
                  7,
                  (v) => '${v.round()} ms',
                  (v) => edit((p) => p.earlyDelay = v),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'WET · Nivel de reverberación',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Text(
              '${(s.wet * 100).round()}%',
              style: const TextStyle(color: _accent, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: s.wet,
          onChanged: supports('wet')
              ? (v) => audio.editReverb((s) => s.wet = v)
              : null,
        ),
        const Row(
          children: [
            Icon(Icons.lock_outline, size: 13, color: _muted),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'DRY · Señal original fija en el motor de otras apps',
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (audio.maxReverbDecay < 20)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Cola máxima confirmada en este dispositivo: ${audio.maxReverbDecay.toStringAsFixed(1)} s.',
              style: const TextStyle(color: _accent, fontSize: 11),
            ),
          ),
        const Text(
          'Arrastra las perillas arriba/abajo. Toca el valor para escribirlo; doble toque en la perilla para restablecer.',
          style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
        ),
        if (!available)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Activa el motor y reproduce audio para conectar la reverberación.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ),
        if (audio.state['reverbError'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              audio.state['reverbError'].toString(),
              style: const TextStyle(color: Color(0xFFE5BB79), fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.only(bottom: 10),
          dense: true,
          title: Text(
            'Alcance con YouTube Music',
            style: TextStyle(fontSize: 11, color: _muted),
          ),
          children: [
            Text(
              'Usa el motor de Android, con controles inspirados en un estudio de reverb. Los controles que el dispositivo no confirma se deshabilitan.\n\nNo incluye los algoritmos de Fruity Reeverb 2 ni sus filtros H.CUT/L.CUT, modulación, BASS/CROSS, MID/SIDE, separación estéreo o mezcla DRY independiente. DENSITY y LATE DEL conservan el significado de sus parámetros Android.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar preset'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Mi sala favorita',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // A dialog's reverse animation can retain its controller until the next frame.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (name != null) {
      final saved = audio.saveReverbPreset(name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Preset guardado'
                  : audio.error ?? 'No se pudo guardar el preset',
            ),
          ),
        );
      }
    }
    text.dispose();
  }
}

class ReverbDial extends StatefulWidget {
  const ReverbDial({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.reset,
    required this.format,
    required this.onChanged,
    this.logarithmic = false,
    this.unsupported = false,
  });
  final String label, description;
  final double value, min, max, reset;
  final bool logarithmic, unsupported;
  final String Function(double) format;
  final ValueChanged<double>? onChanged;
  @override
  State<ReverbDial> createState() => _ReverbDialState();
}

class _ReverbDialState extends State<ReverbDial> {
  double dragPosition = 0;
  double normalized(double v) => widget.logarithmic
      ? math.log(v / widget.min) / math.log(widget.max / widget.min)
      : (v - widget.min) / (widget.max - widget.min);
  double fromPosition(double p) => widget.logarithmic
      ? widget.min * math.pow(widget.max / widget.min, p)
      : widget.min + (widget.max - widget.min) * p;
  void step(double amount) => widget.onChanged?.call(
    fromPosition((normalized(widget.value) + amount).clamp(0, 1)),
  );
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.description,
    child: Column(
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Semantics(
          label: '${widget.label}: ${widget.description}',
          value: widget.format(widget.value),
          increasedValue: widget.onChanged == null
              ? null
              : widget.format(
                  fromPosition((normalized(widget.value) + .01).clamp(0, 1)),
                ),
          decreasedValue: widget.onChanged == null
              ? null
              : widget.format(
                  fromPosition((normalized(widget.value) - .01).clamp(0, 1)),
                ),
          slider: true,
          enabled: widget.onChanged != null,
          onIncrease: widget.onChanged == null ? null : () => step(.01),
          onDecrease: widget.onChanged == null ? null : () => step(-.01),
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: widget.onChanged == null
                  ? null
                  : (_) => dragPosition = normalized(widget.value),
              onVerticalDragUpdate: widget.onChanged == null
                  ? null
                  : (details) {
                      dragPosition = (dragPosition - details.delta.dy / 160)
                          .clamp(0, 1);
                      widget.onChanged!(fromPosition(dragPosition));
                    },
              onDoubleTap: widget.onChanged == null
                  ? null
                  : () => widget.onChanged!(widget.reset),
              child: SizedBox(
                width: 76,
                height: 76,
                child: CustomPaint(
                  painter: _DialPainter(
                    normalized(widget.value),
                    widget.onChanged != null,
                  ),
                ),
              ),
            ),
          ),
        ),
        InkWell(
          onTap: widget.onChanged == null ? null : _enterValue,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 3),
            child: Text(
              widget.unsupported
                  ? 'No disponible'
                  : widget.format(widget.value),
              style: TextStyle(
                fontSize: 11,
                color: widget.onChanged == null ? _muted : _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _enterValue() async {
    final controller = TextEditingController(
      text: widget.value.toStringAsFixed(2),
    );
    String? validation;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final value = double.tryParse(controller.text.replaceAll(',', '.'));
            if (value == null ||
                !value.isFinite ||
                value < widget.min ||
                value > widget.max) {
              setState(
                () => validation = 'Rango: ${widget.min} a ${widget.max}',
              );
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(widget.label),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                helperText: widget.description,
                helperMaxLines: 3,
                errorText: validation,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: submit, child: const Text('Aplicar')),
            ],
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (result != null && mounted) widget.onChanged?.call(result);
    controller.dispose();
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.value, this.enabled);
  final double value;
  final bool enabled;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), r = size.shortestSide * .38;
    final rect = Rect.fromCircle(center: center, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white12;
    canvas.drawArc(rect, math.pi * .75, math.pi * 1.5, false, track);
    canvas.drawArc(
      rect,
      math.pi * .75,
      math.pi * 1.5 * value,
      false,
      track..color = enabled ? _accent : _muted.withValues(alpha: .3),
    );
    canvas.drawCircle(
      center,
      r - 6,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF343E48), Color(0xFF1C242D)],
        ).createShader(rect),
    );
    final angle = math.pi * (.75 + 1.5 * value);
    final offset = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center + offset * r * .45,
      center + offset * r * .68,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = enabled ? _accent : _muted,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.value != value || old.enabled != enabled;
}

class _Envelope extends CustomPainter {
  _Envelope(this.decay, this.delay, this.wet, this.active);
  final double decay, delay, wet;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), axis);
    }
    final start = (delay / 1000 / (decay + .1)).clamp(0, .35) * size.width;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(start, size.height);
    for (var i = 0; i <= 80; i++) {
      final t = i / 80;
      final y = size.height * (1 - wet * math.exp(-6.9 * t));
      path.lineTo(start + t * (size.width - start), y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: active ? .25 : .06),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = active ? _accent : _muted
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Envelope old) =>
      old.decay != decay ||
      old.delay != delay ||
      old.wet != wet ||
      old.active != active;
}
