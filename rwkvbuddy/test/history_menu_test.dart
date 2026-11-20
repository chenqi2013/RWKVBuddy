import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';

class HistoryController extends AgentController {
  HistoryController() : super(autoConnect: false);
  final commands = <Json>[];
  @override
  void send(Json command) => commands.add(command);
}

void main() {
  test(
    'history dates use calendar days including midnight and month boundaries',
    () {
      final now = DateTime(2026, 3, 1, 0, 5);
      expect(
        taskDateLabel(DateTime(2026, 3, 1).toIso8601String(), now: now),
        '今天',
      );
      expect(
        taskDateLabel(
          DateTime(2026, 2, 28, 23, 55).toUtc().toIso8601String(),
          now: now,
        ),
        '昨天',
      );
      expect(
        taskDateLabel(DateTime(2026, 2, 26).toIso8601String(), now: now),
        '3天前',
      );
      expect(taskDateLabel(null, now: now), '');
      expect(taskDateLabel('invalid', now: now), '');
    },
  );
  testWidgets(
    'hover menu pins, unpins and confirms deletion without opening the task',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = HistoryController();
      addTearDown(agent.dispose);
      agent.history = [
        {
          'id': 'first',
          'question': '分析合同',
          'status': 'completed',
          'createdAt': DateTime.now().toIso8601String(),
        },
        {'id': 'second', 'question': '整理表格', 'status': 'completed'},
      ];
      await tester.pumpWidget(MyApp(controller: agent));
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
      final first = find.byKey(const ValueKey('history-item-first'));
      final menu = find.byKey(const ValueKey('history-more-first'));
      expect(menu, findsNothing);
      final initialTitlePosition = tester.getTopLeft(find.text('分析合同'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(900, 100));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(first));
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      expect(tester.getTopLeft(find.text('分析合同')), initialTitlePosition);
      expect(find.byKey(const ValueKey('history-more-second')), findsNothing);
      final titlePosition = tester.getTopLeft(find.text('分析合同'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(900, 100));
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(agent.commands, [
        {'type': 'run.pin', 'runId': 'first', 'pinned': true},
      ]);
      agent.history.first['pinned'] = true;
      agent.update();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      await mouse.moveTo(tester.getCenter(first));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('分析合同')), titlePosition);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();
      expect(agent.commands.last, {
        'type': 'run.pin',
        'runId': 'first',
        'pinned': false,
      });
      await mouse.moveTo(tester.getCenter(first));
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除任务？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(agent.commands.length, 2);
      await mouse.moveTo(tester.getCenter(first));
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      expect(agent.commands.last, {'type': 'run.delete', 'runId': 'first'});
      expect(
        agent.commands.any((command) => command['type'] == 'load'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delete is disabled for the running task', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = HistoryController()
      ..history = [
        {'id': 'active', 'question': '正在处理', 'status': 'running'},
      ]
      ..run = {'id': 'active', 'question': '正在处理', 'status': 'running'}
      ..busy = true;
    addTearDown(agent.dispose);
    await tester.pumpWidget(MyApp(controller: agent));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(900, 100));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('history-item-active'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('history-more-active')));
    await tester.pump(const Duration(milliseconds: 400));
    final deletion = find.widgetWithText(PopupMenuItem<String>, '删除');
    expect(tester.widget<PopupMenuItem<String>>(deletion).enabled, isFalse);
    expect(agent.commands, isEmpty);
    await tester.tapAt(const Offset(900, 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
