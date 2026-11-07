import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/desktop_studio_screen.dart';
import 'package:audiowav/reverb_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(1280, 900), const Size(720, 900)]) {
    testWidgets('Windows source selection and full DSP render at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('audiowav/windows-test');
      final calls = <MethodCall>[];
      final snapshot = {
        'platform': 'windows',
        'running': true,
        'settings': {'enabled': true, 'reverb': 3},
        'captureTargets': [
          {'id': '42', 'label': 'browser.exe · PID 42'},
        ],
        'captureProbe': {
          'mode': 'dsp',
          'active': true,
          'dspReady': true,
          'originalMuted': true,
          'label': 'browser.exe',
          'outputCapabilities': {'reverb': true},
        },
        'externalPlayingSessions': 1,
        'outputDevice': 'Altavoces de prueba',
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'initialize' || call.method == 'snapshot') {
              return snapshot;
            }
            return null;
          });
      final audio = AudioController(channel: channel, supported: true);
      await tester.pumpWidget(
        MaterialApp(home: DesktopStudioScreen(controller: audio)),
      );
      await tester.pumpAndSettle();
      expect(find.text('ESTUDIO PARA WINDOWS · x64'), findsOneWidget);
      expect(find.text('Ecualizador · 5 bandas'), findsOneWidget);
      expect(find.text('Volumen de Windows'), findsOneWidget);
      expect(find.textContaining('adb shell'), findsNothing);
      expect(find.byType(ReverbDial), findsNWidgets(12));
      expect(
        tester
            .widgetList<ReverbDial>(find.byType(ReverbDial))
            .every((dial) => dial.onChanged != null),
        true,
      );
      await tester.ensureVisible(find.text('Detener y restaurar original'));
      await tester.tap(find.text('Detener y restaurar original'));
      await tester.pump();
      expect(calls.any((call) => call.method == 'stopCaptureProbe'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
}
