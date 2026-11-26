import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

import 'windows_keyboard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows native deletion keys edit connection fields',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectionSettings(agent: agent)),
      );
      await tester.tap(find.text('新建连接').last);
      await tester.pumpAndSettle();

      for (final label in ['连接名称', '服务地址', 'API Key / Password', '模型名称（可选）']) {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.tap(field);
        final controller = tester.widget<TextField>(field).controller!;
        await tester.pumpAndSettle();
        await nativeKey(tester, 0, typeText: true);
        expect(controller.text, 'abcd', reason: '$label native typing');
        await nativeKey(tester, 0x08);
        expect(controller.text, 'abc', reason: '$label native Backspace');
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pumpAndSettle();
        await nativeKey(tester, 0x2E);
        expect(controller.text, 'ac', reason: '$label native Delete');
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pumpAndSettle();
        await nativeKey(tester, 0x08);
        await nativeKey(tester, 0x08);
        expect(
          controller.text,
          isEmpty,
          reason: '$label consecutive Backspace',
        );
      }
    },
    skip: !Platform.isWindows,
  );
}
