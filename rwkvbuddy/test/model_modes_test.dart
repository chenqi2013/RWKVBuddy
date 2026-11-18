import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets(
    'local model profile has a separate mode and rejects remote URLs',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectionSettings(agent: agent)),
      );
      await tester.tap(find.text('本地模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建连接').last);
      await tester.pumpAndSettle();
      final address = find.widgetWithText(TextField, '服务地址');
      expect(
        tester.widget<TextField>(address).controller!.text,
        'http://127.0.0.1:8099/v1',
      );
      expect(
        find.widgetWithText(TextField, 'API Key / Password'),
        findsNothing,
      );
      await tester.enterText(address, 'http://192.168.0.219:8123');
      await tester.dragUntilVisible(
        find.text('保存并使用'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并使用'));
      await tester.pumpAndSettle();
      expect(agent.connections, isEmpty);
      await tester.dragUntilVisible(
        find.textContaining('本地模型地址必须'),
        find.byType(ListView),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('本地模型地址必须'), findsOneWidget);
      await tester.dragUntilVisible(
        address,
        find.byType(ListView),
        const Offset(0, 250),
      );
      await tester.pumpAndSettle();
      await tester.enterText(address, 'http://127.0.0.1:8099/v1');
      await tester.dragUntilVisible(
        find.text('保存并使用'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并使用'));
      await tester.pumpAndSettle();
      expect(agent.usesLocalModel, isTrue);
      expect(agent.config['inferenceMode'], 'local');
      expect(agent.config['protocol'], 'python');
      expect(agent.config['concurrency'], 1);
      expect(agent.config['maxTokens'], 1024);
      expect(agent.connectionLabel, contains('本地模型'));
      expect(find.text('本地 RWKV'), findsOneWidget);
      await tester.tap(find.text('在线 API'));
      await tester.pumpAndSettle();
      expect(find.text('本地 RWKV'), findsNothing);
    },
  );

  test(
    'online and local model connections switch independently of rule demo',
    () async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      await agent.saveConnection({
        'id': 'online',
        'name': '千问',
        'baseUrl': 'https://example.org/v1',
      });
      expect(agent.usesLocalModel, isFalse);
      expect(agent.connectionLabel, contains('在线 API'));
      await agent.saveConnection({
        'id': 'local',
        'name': 'RWKV',
        'inferenceMode': 'local',
        'baseUrl': 'http://127.0.0.1:8099',
      });
      expect(agent.usesLocalModel, isTrue);
      agent.activateConnection('online');
      expect(agent.connectionLabel, contains('千问'));
      agent.setMode('local');
      expect(agent.usesLocalModel, isFalse);
      expect(agent.connectionLabel, '本地演示');
    },
  );
}
