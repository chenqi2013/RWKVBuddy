import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';

void main() {
  testWidgets(
    'generation speed appears left of running status, updates and clears for a new request',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      agent.run = {
        'id': 'run',
        'mode': 'rwkv',
        'question': '计算',
        'status': 'running',
      };
      agent.traces = [
        {
          'id': 'model-1',
          'kind': 'model',
          'name': 'rwkv',
          'status': 'running',
          'input': {},
        },
      ];
      await tester.pumpWidget(MyApp(controller: agent));
      const key = Key('generation-speed');
      expect(find.text('-- tokens/s'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(key)).dx,
        lessThan(tester.getCenter(find.text('进行中')).dx),
      );
      agent.traces.last['generation'] = {
        'tokensPerSecond': 24.5,
        'source': 'estimated',
      };
      agent.update();
      await tester.pump();
      expect(find.text('≈ 24.5 tokens/s'), findsOneWidget);
      agent.traces.last['generation'] = {
        'tokensPerSecond': 31.2,
        'source': 'tokens',
      };
      agent.update();
      await tester.pump();
      expect(find.text('31.2 tokens/s'), findsOneWidget);
      expect(find.text('≈ 24.5 tokens/s'), findsNothing);
      agent.traces.last['status'] = 'completed';
      agent.traces.add({
        'id': 'read',
        'kind': 'tool',
        'name': 'read_file',
        'status': 'running',
        'input': {},
      });
      agent.update();
      await tester.pump();
      expect(find.text('31.2 tokens/s'), findsOneWidget);
      agent.traces.add({
        'id': 'model-2',
        'kind': 'model',
        'name': 'rwkv',
        'status': 'running',
        'input': {},
      });
      agent.update();
      await tester.pump();
      expect(find.text('-- tokens/s'), findsOneWidget);
      agent.run!['status'] = 'completed';
      for (final trace in agent.traces) {
        trace['status'] = 'completed';
      }
      agent.update();
      await tester.pump();
      expect(find.byKey(key), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
