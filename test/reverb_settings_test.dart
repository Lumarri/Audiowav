import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/reverb_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the existing room without losing its decay or wet level', () {
    final settings = AudioSettings()..restore({'reverb': 5, 'wet': .7});
    expect(settings.reverbParams.decay, 3.2);
    expect(settings.reverbParams.preDelay, 25);
    expect(settings.wet, .7);
  });
  test(
    'advanced controls and personal presets survive a settings round trip',
    () {
      final settings = AudioSettings();
      settings.reverbParams.decay = 9.8;
      settings.reverbParams.hfRatio = .45;
      settings.reverbProfile = 'user:Mi sala';
      settings.reverbUserPresets = [
        ReverbPreset('Mi sala', 3, settings.reverbParams.toMap(), .35),
      ];
      final restored = AudioSettings()..restore(settings.toMap());
      expect(restored.reverbParams.decay, 9.8);
      expect(restored.reverbParams.hfRatio, .45);
      expect(restored.reverbUserPresets.single.parameters().decay, 9.8);
      expect(restored.reverbProfile, 'user:Mi sala');
      settings.reverbParams.decay = 2;
      expect(restored.reverbUserPresets.single.parameters().decay, 9.8);
    },
  );
  test('invalid values remain within the actual Android parameter ranges', () {
    final p = ReverbParameters.fromMap({
      'decay': 500,
      'preDelay': -30,
      'hfRatio': double.nan,
      'hfLevel': -900,
      'earlyDelay': 999,
    });
    expect(p.decay, 20);
    expect(p.preDelay, 0);
    expect(p.hfRatio, .8);
    expect(p.hfLevel, -90);
    expect(p.earlyDelay, 300);
  });
}
