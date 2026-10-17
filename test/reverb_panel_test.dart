import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/reverb_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'live DSP exposes all twelve reverb dials after original attenuation is confirmed',
    (tester) async {
      final audio = AudioController(supported: true);
      audio.state = {
        'running': true,
        'captureProbe': {
          'mode': 'dsp',
          'active': true,
          'dspReady': true,
          'originalMuted': true,
          'label': 'YouTube Music RVX',
        },
      };
      audio.settings.enabled = true;
      audio.settings.reverb = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ReverbPanel(audio: audio)),
          ),
        ),
      );
      final dials = tester
          .widgetList<ReverbDial>(find.byType(ReverbDial))
          .toList();
      expect(dials, hasLength(12));
      expect(dials.every((dial) => dial.onChanged != null), true);
      expect(dials.any((dial) => dial.label == 'PRE DEL'), true);
      expect(dials.any((dial) => dial.label == 'SIZE'), true);
      expect(
        find.text('DSP propio · YouTube Music RVX · En vivo'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    },
  );

  testWidgets(
    'controls remain visible when switching from local to other apps',
    (tester) async {
      final audio = AudioController(supported: true);
      audio.state = {
        'localDsp': true,
        'playing': true,
        'running': true,
        'capabilities': {'reverb': true},
        'externalCapabilities': {'reverb': true},
        'externalReverbControls': {'earlyLevel': false, 'preDelay': false},
        'externalReverbMaxDecayMs': 7000,
      };
      audio.settings.enabled = true;
      audio.settings.reverb = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: audio,
                builder: (_, _) => ReverbPanel(audio: audio),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ReverbDial), findsNWidgets(12));
      await tester.tap(find.text('Otras apps'));
      await tester.pump();
      expect(find.text('Motor Android · Audio de otras apps'), findsOneWidget);
      expect(find.byType(ReverbDial), findsNWidgets(12));
      final dials = tester.widgetList<ReverbDial>(find.byType(ReverbDial));
      for (final label in [
        'DRY',
        'L.CUT',
        'H.CUT',
        'WIDTH',
        'ER',
        'LATE DEL',
      ]) {
        expect(
          dials.singleWhere((dial) => dial.label == label).onChanged,
          isNull,
        );
      }
      expect(dials.singleWhere((dial) => dial.label == 'DEC').max, 7);
      audio.state = {'running': false};
      audio.selectReverbSource(true);
      await tester.pump();
      expect(find.byType(ReverbDial), findsNWidgets(12));
      expect(
        find.text('Abre un archivo de audio para usar estos controles.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    },
  );

  testWidgets('local DSP provides its own dry, filter and width controls', (
    tester,
  ) async {
    const channel = MethodChannel('audiowav/dsp_panel_test');
    final calls = <Map>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'configure') calls.add(call.arguments as Map);
          return null;
        });
    final audio = AudioController(channel: channel, supported: true);
    audio.state = {
      'localDsp': true,
      'capabilities': {'reverb': true},
      'reverbMaxDecayMs': 20000,
    };
    audio.settings.enabled = true;
    audio.settings.reverb = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ReverbPanel(audio: audio)),
        ),
      ),
    );
    final dials = tester.widgetList<ReverbDial>(find.byType(ReverbDial));
    for (final label in ['DRY', 'L.CUT', 'H.CUT', 'WIDTH', 'PRE DEL', 'SIZE']) {
      expect(
        dials.singleWhere((dial) => dial.label == label).onChanged,
        isNotNull,
      );
    }
    dials.singleWhere((dial) => dial.label == 'DRY').onChanged!(.45);
    await tester.pump(const Duration(milliseconds: 80));
    expect(calls.last['reverbParams']['dry'], .45);
    expect(audio.saveReverbPreset('DSP local'), true);
    expect(audio.settings.reverbUserPresets.single.parameters().dry, .45);
    await tester.pumpWidget(const SizedBox());
    audio.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets(
    'numeric decay edits reach Android and a personal preset can be saved',
    (tester) async {
      const channel = MethodChannel('audiowav/reverb_test');
      final calls = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'configure') calls.add(call.arguments as Map);
            return {
              'running': true,
              'capabilities': {'reverb': true},
              'reverbControls': {'earlyLevel': false},
            };
          });
      final audio = AudioController(channel: channel, supported: true);
      audio.state = {
        'capabilities': {'reverb': true},
        'reverbControls': {'earlyLevel': false},
      };
      audio.settings.reverb = 3;
      audio.settings.enabled = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ListenableBuilder(
                  listenable: audio,
                  builder: (context, child) => ReverbPanel(audio: audio),
                ),
              ),
            ),
          ),
        ),
      );
      final early = tester
          .widgetList<ReverbDial>(find.byType(ReverbDial))
          .singleWhere((d) => d.label == 'ER');
      expect(early.onChanged, isNull);
      final decayValue = find.descendant(
        of: find.byWidgetPredicate((w) => w is ReverbDial && w.label == 'DEC'),
        matching: find.text('1.40 s'),
      );
      await tester.ensureVisible(decayValue);
      await tester.tap(decayValue);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3.75');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 80));
      expect(calls.last['reverbParams']['decay'], 3.75);
      await tester.ensureVisible(find.byTooltip('Guardar preset de reverb'));
      await tester.tap(find.byTooltip('Guardar preset de reverb'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sala personal');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 80));
      expect(audio.settings.reverbUserPresets.single.name, 'Sala personal');
      expect(audio.settings.reverbUserPresets.single.parameters().decay, 3.75);
      expect(calls.last['reverbUserPresets'], hasLength(1));
      final decayDial = find.byWidgetPredicate(
        (w) => w is ReverbDial && w.label == 'DEC',
      );
      await tester.ensureVisible(decayDial);
      await tester.drag(decayDial, const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      expect(audio.settings.reverbParams.decay, greaterThan(3.75));
      expect(audio.settings.reverbUserPresets.single.parameters().decay, 3.75);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
