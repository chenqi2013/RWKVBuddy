import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('local models use GGUF import without an HTTP connection form', (
    tester,
  ) async {
    final agent = AgentController(autoConnect: false);
    addTearDown(agent.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectionSettings(agent: agent)),
    );
    await tester.tap(find.text('本地模型'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-gguf')), findsOneWidget);
    expect(find.textContaining('无需启动 HTTP 服务'), findsOneWidget);
    expect(find.text('新建连接'), findsNothing);
    expect(find.widgetWithText(TextField, '服务地址'), findsNothing);
    await tester.tap(find.text('在线 API'));
    await tester.pumpAndSettle();
    expect(find.text('新建连接'), findsOneWidget);
  });

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
  testWidgets('API JSON output can be saved and restored per connection', (
    tester,
  ) async {
    final agent = AgentController(autoConnect: false);
    addTearDown(agent.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectionSettings(agent: agent)),
    );
    await tester.tap(find.text('新建连接').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '服务地址'),
      'http://192.168.0.115:8104/v1',
    );
    final toggle = find.widgetWithText(SwitchListTile, 'JSON 输出模式');
    await tester.dragUntilVisible(
      toggle,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.dragUntilVisible(
      find.text('保存并使用'),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并使用'));
    await tester.pumpAndSettle();
    expect(agent.config['inferenceMode'], 'online');
    expect(agent.config['jsonOutput'], isTrue);
    expect(agent.config['baseUrl'], 'http://192.168.0.115:8104/v1');
    await tester.tap(find.byTooltip('编辑连接'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      toggle,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
  testWidgets(
    'existing RWKV profiles default to JSON and allow explicit disabling',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      await agent.saveConnection({
        'id': 'existing-rwkv',
        'name': '局域网 RWKV',
        'baseUrl': 'http://192.168.0.115:8104/v1',
        'protocol': 'chat',
        'model': 'rwkv7-g1m-preview-13.3b',
      });
      await tester.pumpWidget(
        MaterialApp(home: ConnectionSettings(agent: agent)),
      );
      await tester.tap(find.byTooltip('编辑连接'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, 'JSON 输出模式');
      await tester.dragUntilVisible(
        toggle,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.dragUntilVisible(
        find.text('保存并使用'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并使用'));
      await tester.pumpAndSettle();
      expect(agent.config['jsonOutput'], isFalse);
      await tester.tap(find.byTooltip('编辑连接'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        toggle,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    },
  );
}
