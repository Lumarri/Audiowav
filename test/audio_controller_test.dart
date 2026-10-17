import 'package:audiowav/audio_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('audiowav/audio_test');
  late List<MethodCall> calls;
  late AudioController controller;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') {
            return {
              'running': false,
              'settings': {
                'preset': 'Rock',
                'bands': [4, 2, -2, 3, 5],
                'gain': 3.0,
              },
              'capabilities': {'equalizer': true},
            };
          }
          if (call.method == 'snapshot') return {'running': true};
          return null;
        });
    controller = AudioController(channel: channel, supported: true);
  });
  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('restores settings without starting the foreground service', () async {
    await controller.initialize();
    expect(controller.settings.preset, 'Rock');
    expect(controller.settings.gain, 3);
    expect(controller.settings.enabled, false);
    expect(controller.available('equalizer'), true);
    expect(calls.map((c) => c.method), ['initialize']);
  });
  testWidgets('slider sends immediately and retains the final value', (
    tester,
  ) async {
    controller.update((s) => s.gain = 2);
    controller.update((s) => s.gain = 4);
    controller.update((s) => s.gain = 7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    final configurations = calls.where((c) => c.method == 'configure').toList();
    expect(configurations, hasLength(2));
    expect(configurations.first.arguments['gain'], 2);
    expect(configurations.last.arguments['gain'], 7);
  });
  testWidgets('continuous dragging applies intermediate audio settings', (
    tester,
  ) async {
    for (var i = 1; i <= 10; i++) {
      controller.update((s) => s.gain = i.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    final duringDrag = calls.where((c) => c.method == 'configure').toList();
    expect(duringDrag.length, greaterThan(2));
    expect(duringDrag.first.arguments['gain'], 1);
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      calls.lastWhere((c) => c.method == 'configure').arguments['gain'],
      10,
    );
    await tester.pump(const Duration(milliseconds: 80));
  });
  test('clamps persisted controls to supported ranges', () {
    final settings = AudioSettings()
      ..restore({
        'bands': [99, -99, 0, 1, 2],
        'gain': 999,
        'bass': -1,
        'balance': 10,
        'reverb': 100,
      });
    expect(settings.bands, [12, -12, 0, 1, 2]);
    expect(settings.gain, 12);
    expect(settings.bass, 0);
    expect(settings.balance, 1);
    expect(settings.reverb, 6);
  });
  test('unsupported platforms never call the native audio API', () async {
    final unsupported = AudioController(channel: channel, supported: false);
    await unsupported.initialize();
    await unsupported.openFile();
    expect(unsupported.available('equalizer'), false);
    expect(calls, isEmpty);
    unsupported.dispose();
  });
  test('native decay limits adapt the dial without disabling it', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'running': true,
            'reverbMaxDecayMs': 7000,
            'settings': {
              'reverb': 3,
              'reverbParams': {'decay': 12},
            },
            'capabilities': {'reverb': true},
            'reverbControls': {'decay': true},
          },
        );
    await controller.initialize();
    expect(controller.maxReverbDecay, 7);
    expect(controller.settings.reverbParams.decay, 7);
    expect(controller.reverbControlAvailable('decay'), true);
  });

  test('local DSP exposes controls without claiming them for other apps', () {
    controller.state = {
      'capabilities': {'reverb': true},
      'reverbMaxDecayMs': 7000,
    };
    expect(controller.reverbControlAvailable('dry'), false);
    expect(controller.reverbControlAvailable('lowCut'), false);
    controller.state = {
      'localDsp': true,
      'capabilities': {'reverb': true},
      'reverbMaxDecayMs': 20000,
      'externalReverbMaxDecayMs': 7000,
    };
    expect(controller.reverbControlAvailable('dry'), true);
    expect(controller.maxReverbDecay, 20);
    controller.state['localSampleRate'] = 16000;
    expect(controller.maxReverbHighCut, 7200);
  });

  test('DSP controls survive preset storage and old settings migration', () {
    final settings = AudioSettings()..restore({});
    expect(settings.reverbParams.dry, 1);
    expect(settings.reverbParams.lowCut, 20);
    expect(settings.reverbParams.highCut, 18000);
    expect(settings.reverbParams.width, 1);
    settings.restore({
      'reverbParams': {'dry': .4, 'lowCut': 140, 'highCut': 8500, 'width': 1.5},
    });
    final copy = AudioSettings()..restore(settings.toMap());
    expect(copy.reverbParams.dry, .4);
    expect(copy.reverbParams.lowCut, 140);
    expect(copy.reverbParams.highCut, 8500);
    expect(copy.reverbParams.width, 1.5);
  });
}
