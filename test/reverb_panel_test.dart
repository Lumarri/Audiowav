import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/reverb_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
