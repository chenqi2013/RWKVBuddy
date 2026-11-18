import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps desktop deletion available when Windows supplies a physical key without
/// the logical Backspace/Delete key expected by Flutter's default shortcuts.
class WindowsTextEditing extends StatelessWidget {
  const WindowsTextEditing({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Widget child;
  final bool enabled;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!enabled ||
        defaultTargetPlatform != TargetPlatform.windows ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final backward =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.physicalKey == PhysicalKeyboardKey.backspace;
    final forward =
        event.logicalKey == LogicalKeyboardKey.delete ||
        event.physicalKey == PhysicalKeyboardKey.delete;
    if (!backward && !forward) return KeyEventResult.ignored;

    // Let the native IME edit its pending composition. Once committed, use
    // EditableText's action so Unicode boundaries, selection and undo stay intact.
    final value = controller.value;
    if (value.isComposingRangeValid && !value.composing.isCollapsed) {
      return KeyEventResult.skipRemainingHandlers;
    }
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return KeyEventResult.ignored;
    final intent = DeleteCharacterIntent(forward: forward);
    final action = Actions.maybeFind<DeleteCharacterIntent>(context);
    if (action == null || !action.isEnabled(intent)) {
      return KeyEventResult.ignored;
    }
    Actions.invoke(context, intent);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKeyEvent,
    child: child,
  );
}
