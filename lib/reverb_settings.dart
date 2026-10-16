class ReverbParameters {
  ReverbParameters({
    this.decay = 1.4,
    this.preDelay = 10,
    this.size = 85,
    this.diffusion = 100,
    this.hfRatio = .8,
    this.hfLevel = -6,
    this.earlyLevel = .25,
    this.earlyDelay = 7,
  });
  double decay,
      preDelay,
      size,
      diffusion,
      hfRatio,
      hfLevel,
      earlyLevel,
      earlyDelay;

  factory ReverbParameters.legacy(int mode) => ReverbParameters(
    decay: [1.4, .4, .85, 1.4, 1.8, 3.2, 2.2][mode.clamp(0, 6)],
    preDelay: mode >= 4 ? 25 : 10,
    size: mode == 6 ? 100 : 85,
    hfRatio: mode == 6 ? 1.1 : .8,
    hfLevel: mode == 6 ? -2 : -6,
    earlyDelay: mode >= 4 ? 20 : 7,
  );

  factory ReverbParameters.fromMap(Map map, {int legacyMode = 3}) {
    final p = ReverbParameters.legacy(legacyMode);
    double value(String key, double fallback, double min, double max) {
      final raw = map[key];
      return raw is num && raw.isFinite
          ? raw.toDouble().clamp(min, max)
          : fallback;
    }

    p.decay = value('decay', p.decay, .1, 20);
    p.preDelay = value('preDelay', p.preDelay, 0, 100);
    p.size = value('size', p.size, 0, 100);
    p.diffusion = value('diffusion', p.diffusion, 0, 100);
    p.hfRatio = value('hfRatio', p.hfRatio, .1, 2);
    p.hfLevel = value('hfLevel', p.hfLevel, -90, 0);
    p.earlyLevel = value('earlyLevel', p.earlyLevel, 0, 1);
    p.earlyDelay = value('earlyDelay', p.earlyDelay, 0, 300);
    return p;
  }
  Map<String, double> toMap() => {
    'decay': decay,
    'preDelay': preDelay,
    'size': size,
    'diffusion': diffusion,
    'hfRatio': hfRatio,
    'hfLevel': hfLevel,
    'earlyLevel': earlyLevel,
    'earlyDelay': earlyDelay,
  };
}

class ReverbPreset {
  const ReverbPreset(this.name, this.mode, this.values, this.wet);
  final String name;
  final int mode;
  final Map<String, double> values;
  final double wet;
  ReverbParameters parameters() =>
      ReverbParameters.fromMap(values, legacyMode: mode);
  Map<String, dynamic> toMap() => {
    'name': name,
    'mode': mode,
    'values': values,
    'wet': wet,
  };
  static ReverbPreset? fromMap(Map map) {
    final name = map['name'];
    if (name is! String || name.trim().isEmpty || name.length > 32) return null;
    final mode = (map['mode'] as num? ?? 3).toInt().clamp(1, 6);
    final p = ReverbParameters.fromMap(
      map['values'] as Map? ?? {},
      legacyMode: mode,
    );
    return ReverbPreset(
      name.trim(),
      mode,
      p.toMap(),
      (map['wet'] as num? ?? .25).toDouble().clamp(0, 1),
    );
  }
}

const reverbPresets = [
  ReverbPreset('Room', 1, {
    'decay': .45,
    'preDelay': 7,
    'size': 40,
    'diffusion': 75,
    'hfRatio': .65,
    'hfLevel': -8,
    'earlyLevel': .35,
    'earlyDelay': 5,
  }, .22),
  ReverbPreset('Hall', 4, {
    'decay': 2.6,
    'preDelay': 28,
    'size': 90,
    'diffusion': 95,
    'hfRatio': .75,
    'hfLevel': -5,
    'earlyLevel': .25,
    'earlyDelay': 15,
  }, .3),
  ReverbPreset('Plate', 6, {
    'decay': 2.2,
    'preDelay': 15,
    'size': 100,
    'diffusion': 100,
    'hfRatio': 1.1,
    'hfLevel': -2,
    'earlyLevel': .1,
    'earlyDelay': 0,
  }, .28),
  ReverbPreset('Vocal', 2, {
    'decay': 1.35,
    'preDelay': 45,
    'size': 70,
    'diffusion': 90,
    'hfRatio': .6,
    'hfLevel': -9,
    'earlyLevel': .18,
    'earlyDelay': 10,
  }, .2),
  ReverbPreset('Ambient', 5, {
    'decay': 8,
    'preDelay': 65,
    'size': 100,
    'diffusion': 100,
    'hfRatio': .65,
    'hfLevel': -10,
    'earlyLevel': .08,
    'earlyDelay': 30,
  }, .38),
  ReverbPreset('Cathedral', 5, {
    'decay': 12,
    'preDelay': 90,
    'size': 100,
    'diffusion': 95,
    'hfRatio': .7,
    'hfLevel': -7,
    'earlyLevel': .35,
    'earlyDelay': 45,
  }, .35),
];
