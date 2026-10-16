import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const equalizerPresets = <String, List<double>>{
  'Plano': [0, 0, 0, 0, 0],
  'Potente': [5, 3, -1, 2, 4],
  'Rock': [4, 2, -2, 3, 5],
  'Voces': [-3, -1, 4, 3, 0],
  'Electrónica': [6, 3, -2, 2, 5],
  'Acústico': [2, 1, 2, 3, 2],
};

class AudioSettings {
  bool enabled = false;
  String preset = 'Plano';
  List<double> bands = [0, 0, 0, 0, 0];
  double bass = 0, gain = 0, balance = 0, wet = .25;
  int reverb = 0;
  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'preset': preset,
    'bands': bands,
    'bass': bass,
    'gain': gain,
    'balance': balance,
    'reverb': reverb,
    'wet': wet,
  };
  void restore(Map<dynamic, dynamic> map) {
    enabled = map['enabled'] == true;
    preset = map['preset'] as String? ?? 'Plano';
    final saved = map['bands'];
    if (saved is List && saved.length == 5) {
      bands = saved
          .map((v) => (v as num).toDouble().clamp(-12.0, 12.0))
          .toList();
    }
    bass = (map['bass'] as num? ?? 0).toDouble().clamp(0, 1);
    gain = (map['gain'] as num? ?? 0).toDouble().clamp(0, 12);
    balance = (map['balance'] as num? ?? 0).toDouble().clamp(-1, 1);
    reverb = (map['reverb'] as num? ?? 0).toInt().clamp(0, 6);
    wet = (map['wet'] as num? ?? .25).toDouble().clamp(0, 1);
  }
}

class AudioController extends ChangeNotifier {
  AudioController({MethodChannel? channel, bool? supported})
    : channel = channel ?? const MethodChannel('audiowav/audio'),
      supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  final MethodChannel channel;
  final bool supported;
  final settings = AudioSettings();
  Map<dynamic, dynamic> state = {};
  Timer? _poll, _debounce;
  bool _disposed = false, _polling = false;
  bool loading = true;
  String? error;
  bool get running => state['running'] == true;
  bool get playing => state['playing'] == true;
  bool get hasTrack => state['hasTrack'] == true;
  String get track => state['title'] as String? ?? 'Tu próxima canción';
  int get position => (state['position'] as num? ?? 0).toInt();
  int get duration => (state['duration'] as num? ?? 0).toInt();
  int get sessions => (state['sessions'] as num? ?? 0).toInt();
  double get volume => (state['volume'] as num? ?? .5).toDouble();
  bool available(String effect) =>
      supported && (state['capabilities'] as Map?)?[effect] == true;

  Future<void> initialize() async {
    if (supported) {
      final data = await _invoke<Map>('initialize');
      if (_disposed) return;
      if (data != null) {
        settings.restore(data['settings'] as Map? ?? {});
        state = data;
      }
      settings.enabled = running && settings.enabled;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    }
    loading = false;
    _notify();
  }

  Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      error = e.message ?? 'No se pudo acceder al audio.';
    } on MissingPluginException {
      error = 'El motor de audio solo está disponible en Android.';
    }
    _notify();
    return null;
  }

  Future<void> refresh() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final data = await _invoke<Map>('snapshot');
      if (data != null && !_disposed) {
        final wasRunning = running;
        state = data;
        if (wasRunning && !running) settings.enabled = false;
        _notify();
      }
    } finally {
      _polling = false;
    }
  }

  void update(void Function(AudioSettings) change) {
    change(settings);
    error = null;
    _notify();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () async {
      await _invoke('configure', settings.toMap());
      await refresh();
    });
  }

  void selectPreset(String name) => update((s) {
    s.preset = name;
    s.bands = List.of(equalizerPresets[name]!);
  });
  Future<void> openFile() async {
    error = null;
    await _invoke('openFile');
    await refresh();
  }

  Future<void> togglePlayback() async {
    await _invoke('togglePlayback');
    await refresh();
  }

  Future<void> seek(double milliseconds) async {
    await _invoke('seek', milliseconds.round());
    await refresh();
  }

  Future<void> setVolume(double value) async {
    await _invoke('volume', value);
    await refresh();
  }

  Future<void> stop() async {
    _debounce?.cancel();
    settings.enabled = false;
    await _invoke('stop');
    await refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
