import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';

void main() {
  testWidgets(
    'streaming follows down smoothly, pauses for reading and resumes at bottom',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      agent.run = {'id': 'stream', 'question': '分析表格', 'status': 'running'};
      agent.busy = true;
      final draft = List.generate(
        35,
        (number) => '第 $number 项数据分析。',
      ).join('\n\n');
      agent.traces = [
        for (var number = 0; number < 12; number++)
          {
            'id': 'tool-$number',
            'kind': 'tool',
            'name': 'calculator',
            'status': 'completed',
            'input': {'expression': '6*7'},
            'output': '{"result":42}',
          },
        {
          'id': 'model',
          'kind': 'model',
          'name': 'test-model',
          'status': 'running',
          'input': {'project': {}},
          'progress': '正在整理表格结论。',
          'answerPreview': draft,
        },
      ];
      await tester.pumpWidget(MyApp(controller: agent));
      await tester.pump();
      final list = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('stream')),
      );
      final scroll = list.controller!;
      Future<void> followToBottom() async {
        for (var frame = 0; frame < 70; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      }

      await followToBottom();
      var previous = scroll.offset;
      for (var number = 0; number < 5; number++) {
        agent.traces.last['answerPreview'] =
            '${agent.traces.last['answerPreview']}\n\n新增结论 $number';
        agent.update();
        await tester.pump();
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(scroll.offset, greaterThanOrEqualTo(previous));
          previous = scroll.offset;
        }
      }
      await followToBottom();

      agent.traces.last['answerPreview'] =
          '${agent.traces.last['answerPreview']}\n\n正在继续生成。';
      agent.update();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.drag(
        find.byKey(const ValueKey('stream')),
        const Offset(0, 300),
      );
      await tester.pump(const Duration(seconds: 1));
      final position = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(100));
      agent.traces.last['answerPreview'] =
          '${agent.traces.last['answerPreview']}\n\n手动阅读时新增结论。';
      agent.update();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, closeTo(position, 1));

      await tester.drag(
        find.byKey(const ValueKey('stream')),
        const Offset(0, -1000),
      );
      await followToBottom();
      agent.traces.last['answerPreview'] =
          '${agent.traces.last['answerPreview']}\n\n手动回到底部后继续跟随。';
      agent.update();
      await tester.pump();
      await followToBottom();

      await tester.drag(
        find.byKey(const ValueKey('stream')),
        const Offset(0, 300),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('跳到最新内容'));
      await followToBottom();
      agent.traces.last['answerPreview'] =
          '${agent.traces.last['answerPreview']}\n\n恢复自动跟随。';
      agent.update();
      await tester.pump();
      await followToBottom();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const ValueKey('stream'))),
          scrollDelta: const Offset(0, -250),
        ),
      );
      await tester.pump();
      final wheelPosition = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(100));
      agent.traces.last['answerPreview'] =
          '${agent.traces.last['answerPreview']}\n\n滚轮阅读时新增结论。';
      agent.update();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, closeTo(wheelPosition, 1));
      await tester.tap(find.byTooltip('跳到最新内容'));
      await followToBottom();
      final completeDraft = agent.traces.last['answerPreview'] as String;
      agent.traces.last.addAll({
        'status': 'completed',
        'output': '{"answer":"完成"}',
      });
      agent.update();
      await tester.pump();
      await followToBottom();
      previous = scroll.offset;
      agent.run!.addAll({'status': 'completed', 'answer': completeDraft});
      agent.busy = false;
      agent.update();
      await tester.pump();
      for (var frame = 0; frame < 70; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, greaterThanOrEqualTo(previous));
        previous = scroll.offset;
      }
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      expect(find.text('生成结果'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history starts at top and a new running turn follows content', (
    tester,
  ) async {
    final agent = AgentController(autoConnect: false);
    addTearDown(agent.dispose);
    final answer = List.generate(50, (number) => '结论 $number').join('\n\n');
    agent.run = {
      'id': 'history',
      'question': '历史问题',
      'status': 'completed',
      'answer': answer,
    };
    await tester.pumpWidget(MyApp(controller: agent));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('history')))
        .controller!;
    expect(scroll.offset, 0);
    expect(scroll.position.maxScrollExtent, greaterThan(500));
    agent.turns = [agent.run!];
    agent.run = {'id': 'next', 'question': '继续分析', 'status': 'running'};
    agent.busy = true;
    agent.update();
    await tester.pump();
    for (var frame = 0; frame < 70; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    agent.busy = false;
    agent.turns = [];
    agent.run = {
      'id': 'other-history',
      'question': '另一条历史',
      'status': 'completed',
      'answer': answer,
    };
    agent.update();
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed delivery shows a marked draft without presenting error report as generated result',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      agent.run = {
        'id': 'failed',
        'question': '生成报告',
        'status': 'failed',
        'answer': '',
        'error': '输出达到上限',
        'report': '输出达到上限\n\n## 来源\n\n- E1',
      };
      agent.traces = [
        {
          'id': 'model',
          'kind': 'model',
          'name': 'test',
          'status': 'failed',
          'input': {},
          'answerPreview': '尚未提交的片段',
        },
      ];
      await tester.pumpWidget(MyApp(controller: agent));
      await tester.pumpAndSettle();
      expect(find.text('生成结果'), findsNothing);
      expect(find.text('回答草稿 · 已中断，未作为结果提交'), findsOneWidget);
      expect(find.text('尚未提交的片段'), findsOneWidget);
      expect(find.text('来源'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
