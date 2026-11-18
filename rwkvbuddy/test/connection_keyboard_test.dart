import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

void main() {
  testWidgets(
    'Windows connection inputs support Backspace and Delete',
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
        await tester.enterText(field, 'ab中文cd');
        final controller = tester.widget<TextField>(field).controller!;
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'ab中文c', reason: '$label Backspace');
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();
        expect(controller.text, 'ab文c', reason: '$label Delete');
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 3,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'ac', reason: '$label selection');
        controller.value = const TextEditingValue(
          text: 'ab中文cd',
          selection: TextSelection.collapsed(offset: 6),
        );
        await tester.sendKeyEvent(
          // Some Windows input methods change the logical key. The physical
          // Backspace must still work after the composition is committed.
          LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.backspace,
        );
        await tester.pump();
        expect(
          controller.text,
          'ab中文c',
          reason: '$label Windows physical Backspace fallback',
        );
        await tester.enterText(field, 'a😀');
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'a', reason: '$label Unicode deletion');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, isEmpty, reason: '$label repeat at start');
        controller.value = const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        );
        final handled = await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(handled, isFalse, reason: '$label IME owns active composition');
        expect(
          controller.text,
          'ni',
          reason: '$label preserve IME composition',
        );
        controller.clear();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
