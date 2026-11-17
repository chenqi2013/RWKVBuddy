import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';

void main() {
  testWidgets(
    'streaming and result handoff preserve the chosen conversation position',
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
      scroll.jumpTo(scroll.position.maxScrollExtent - 50);
      await tester.pump();
      final position = scroll.offset;
      for (var number = 0; number < 5; number++) {
        agent.traces.last['answerPreview'] = '$draft\n\n新增结论 $number';
        agent.update();
        await tester.pump();
        await tester.pump();
        expect(scroll.offset, closeTo(position, 1));
      }
      final completeDraft = agent.traces.last['answerPreview'] as String;
      agent.traces.last.addAll({
        'status': 'completed',
        'output': '{"answer":"完成"}',
      });
      agent.update();
      await tester.pump();
      expect(scroll.offset, closeTo(position, 1));
      agent.run!.addAll({'status': 'completed', 'answer': completeDraft});
      agent.busy = false;
      agent.update();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(position, 1));
      expect(find.text('生成结果'), findsOneWidget);
      await tester.tap(find.byTooltip('跳到最新内容'));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      expect(tester.takeException(), isNull);
    },
  );

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
