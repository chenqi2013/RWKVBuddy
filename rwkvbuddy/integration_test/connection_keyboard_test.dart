import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

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

      Future<void> nativeKey(int key, {bool typeText = false}) async {
        // Allow the native text-input client to receive selection changes before
        // injecting another key; pumpAndSettle only waits for Flutter frames.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-Command',
          '''
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BuddyKeyboardTest {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint command);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, UIntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint key, uint mapType);
}
'@
\$app = Get-Process -Id $pid
[BuddyKeyboardTest]::SetForegroundWindow(\$app.MainWindowHandle) | Out-Null
if ([BuddyKeyboardTest]::GetForegroundWindow() -ne \$app.MainWindowHandle) {
  throw 'Unable to focus the test application'
}
if (${typeText ? '\$true' : '\$false'}) {
  \$view = [BuddyKeyboardTest]::GetWindow(\$app.MainWindowHandle, 5)
  foreach (\$character in 'abcd'.ToCharArray()) {
    [BuddyKeyboardTest]::PostMessage(\$view, 0x0102, [UIntPtr][uint32]\$character, [IntPtr]::Zero) | Out-Null
  }
} else {
\$scan = [byte][BuddyKeyboardTest]::MapVirtualKey($key, 0)
\$flags = if ($key -eq 0x2E) { 1 } else { 0 }
[BuddyKeyboardTest]::keybd_event($key, \$scan, \$flags, [UIntPtr]::Zero)
[BuddyKeyboardTest]::keybd_event($key, \$scan, (\$flags -bor 2), [UIntPtr]::Zero)
}
''',
        ], runInShell: false);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }

      for (final label in ['连接名称', '服务地址', 'API Key / Password', '模型名称（可选）']) {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.tap(field);
        final controller = tester.widget<TextField>(field).controller!;
        await tester.pumpAndSettle();
        await nativeKey(0, typeText: true);
        expect(controller.text, 'abcd', reason: '$label native typing');
        await nativeKey(0x08);
        expect(controller.text, 'abc', reason: '$label native Backspace');
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pumpAndSettle();
        await nativeKey(0x2E);
        expect(controller.text, 'ac', reason: '$label native Delete');
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pumpAndSettle();
        await nativeKey(0x08);
        await nativeKey(0x08);
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
