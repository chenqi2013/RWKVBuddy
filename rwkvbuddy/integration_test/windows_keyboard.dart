import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<void> nativeKey(
  WidgetTester tester,
  int key, {
  bool typeText = false,
  bool zeroScan = false,
  int repeats = 0,
}) async {
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
if (${typeText ? '\$true' : '\$false'}) {
  \$view = [BuddyKeyboardTest]::GetWindow(\$app.MainWindowHandle, 5)
  foreach (\$character in 'abcd'.ToCharArray()) {
    [BuddyKeyboardTest]::PostMessage(\$view, 0x0102, [UIntPtr][uint32]\$character, [IntPtr]::Zero) | Out-Null
  }
} elseif (${zeroScan ? '\$true' : '\$false'}) {
  \$view = [BuddyKeyboardTest]::GetWindow(\$app.MainWindowHandle, 5)
  [BuddyKeyboardTest]::PostMessage(\$view, 0x0100, [UIntPtr][uint32]$key, [IntPtr]1) | Out-Null
  for (\$repeat = 0; \$repeat -lt $repeats; \$repeat++) {
    [BuddyKeyboardTest]::PostMessage(\$view, 0x0100, [UIntPtr][uint32]$key, [IntPtr]0x40000001) | Out-Null
  }
  [BuddyKeyboardTest]::PostMessage(\$view, 0x0101, [UIntPtr][uint32]$key, [IntPtr]0xC0000001L) | Out-Null
} else {
\$scan = [byte][BuddyKeyboardTest]::MapVirtualKey($key, 0)
\$flags = if ($key -in @(0x2E, 0x24, 0x23, 0x25, 0x26, 0x27, 0x28)) { 1 } else { 0 }
[BuddyKeyboardTest]::keybd_event($key, \$scan, \$flags, [UIntPtr]::Zero)
for (\$repeat = 0; \$repeat -lt $repeats; \$repeat++) {
  [BuddyKeyboardTest]::keybd_event($key, \$scan, \$flags, [UIntPtr]::Zero)
}
[BuddyKeyboardTest]::keybd_event($key, \$scan, (\$flags -bor 2), [UIntPtr]::Zero)
}
''',
  ], runInShell: false);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}
