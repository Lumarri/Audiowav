import 'package:audiowav/audio_controller.dart';
import 'package:audiowav/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile studio renders and presets reach Android', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('audiowav/widget_test');
    final configurations = <Map>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'configure') {
            configurations.add(call.arguments as Map);
          }
          return {
            'running': true,
            'capabilities': {
              'equalizer': true,
              'bass': true,
              'gain': true,
              'reverb': true,
            },
          };
        });
    final controller = AudioController(channel: channel, supported: true);
    await tester.pumpWidget(AudiowavApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('audiowav'), findsOneWidget);
    await tester.ensureVisible(find.text('Rock'));
    await tester.tap(find.text('Rock'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(configurations.last['bands'], [4, 2, -2, 3, 5]);
    await tester.scrollUntilVisible(
      find.text('Abrir una canción'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Abrir una canción'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
