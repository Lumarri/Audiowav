import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/capture_probe_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'denied Android consent clears pending state and shows the reason',
    (tester) async {
      const channel = MethodChannel('audiowav/probe_denied_test');
      var requests = 0;
      const reason = 'Prueba cancelada: no se autorizó el permiso de audio.';
      final state = <String, dynamic>{
        'captureSupported': true,
        'captureTargets': [
          {'id': 'com.spotify.music', 'label': 'Spotify'},
        ],
        'captureProbe': {'status': 'idle', 'active': false},
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'startCaptureProbe') {
              requests++;
              throw PlatformException(
                code: 'CAPTURE_PERMISSION',
                message: reason,
              );
            }
            return state;
          });
      final audio = AudioController(channel: channel, supported: true)
        ..state = state;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: audio,
                builder: (_, _) => CaptureProbePanel(audio: audio),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Probar 20 segundos'));
      await tester.tap(find.text('Probar 20 segundos'));
      await tester.pump();
      expect(audio.probePending, false);
      expect(audio.captureActive, false);
      expect(find.text(reason), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'capture requires pressing the button and uses the selected app',
    (tester) async {
      const channel = MethodChannel('audiowav/probe_test');
      final calls = <MethodCall>[];
      final state = <String, dynamic>{
        'captureSupported': true,
        'captureTargets': [
          {
            'id': 'app.rvx.android.apps.youtube.music',
            'label': 'YouTube Music RVX',
          },
          {'id': 'com.spotify.music', 'label': 'Spotify'},
        ],
        'captureProbe': {'status': 'idle', 'active': false},
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'startCaptureProbe') {
              state['captureProbe'] = {
                'status': 'running',
                'active': true,
                'elapsedMs': 2000,
                'signalDetected': false,
              };
            }
            if (call.method == 'stopCaptureProbe') {
              state['captureProbe'] = {
                'status': 'stopped',
                'active': false,
                'signalDetected': false,
              };
            }
            return call.method == 'snapshot' ? state : null;
          });
      final audio = AudioController(channel: channel, supported: true)
        ..state = state;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: audio,
                builder: (_, _) => CaptureProbePanel(audio: audio),
              ),
            ),
          ),
        ),
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('YouTube Music RVX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spotify').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Probar 20 segundos'));
      await tester.tap(find.text('Probar 20 segundos'));
      await tester.pump();
      expect(calls.first.method, 'startCaptureProbe');
      expect(calls.first.arguments, 'com.spotify.music');
      expect(find.text('Detener prueba'), findsOneWidget);
      await tester.tap(find.text('Detener prueba'));
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'stopCaptureProbe'),
        hasLength(1),
      );
      expect(find.text('Prueba detenida sin confirmar señal.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('silence result is not presented as a definitive capture block', (
    tester,
  ) async {
    final audio = AudioController(supported: true)
      ..state = {
        'captureSupported': true,
        'captureTargets': [],
        'captureProbe': {
          'status': 'no_signal',
          'active': false,
          'elapsedMs': 20000,
          'peakDb': -120,
        },
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CaptureProbePanel(audio: audio)),
        ),
      ),
    );
    expect(find.textContaining('No se confirmó señal.'), findsOneWidget);
    expect(find.textContaining('puede estar bloqueando'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    audio.dispose();
  });
}
