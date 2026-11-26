import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

class GGUFPicker extends FileSelectorPlatform {
  GGUFPicker(this.path);
  final String path;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile(path);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const modelPath = String.fromEnvironment('GGUF_TEST_PATH');
  testWidgets(
    'imports real GGUF through the UI, infers and unloads its bundled process',
    (tester) async {
      final temporary = await Directory.systemTemp.createTemp('buddy-gguf-ui-');
      final agent = AgentController(
        serviceEnvironment: {'RWKVBUDDY_DATA_DIR': '${temporary.path}/runs'},
      );
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = GGUFPicker(modelPath);
      addTearDown(() async {
        FileSelectorPlatform.instance = previous;
        await agent.shutdown();
        agent.dispose();
        await temporary.delete(recursive: true);
      });
      Future<void> waitUntil(bool Function() condition) async {
        for (var i = 0; i < 900 && !condition(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          condition(),
          isTrue,
          reason: '${agent.error} ${agent.localModelState}',
        );
      }

      await tester.pumpWidget(
        MaterialApp(home: ConnectionSettings(agent: agent)),
      );
      await waitUntil(() => agent.connected);
      expect(agent.localRuntimeAvailable, isTrue);
      await tester.tap(find.text('本地模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-gguf')));
      await waitUntil(
        () =>
            agent.localModelState['status'] == 'ready' &&
            !agent.localModelOperation,
      );
      expect(agent.usesLocalModel, isTrue);
      expect(agent.config['localModelId'], agent.localModels.single['id']);
      expect(agent.config['protocol'], 'native');
      expect(agent.config['baseUrl'], isEmpty);
      final result = await agent.testConnection(agent.config, generate: true);
      expect(result['ok'], isTrue, reason: result.toString());
      agent.newTask();
      agent.start('36乘以12等于多少？请直接回答。');
      await waitUntil(() => !agent.busy);
      expect(agent.run?['status'], 'completed', reason: agent.run.toString());
      expect(agent.run?['answer'], contains('432'));
      await agent.stopLocalModel();
      expect(agent.localModelState['status'], 'idle');
      agent.start('你好');
      expect(agent.error, contains('加载此模型'));
      expect(agent.busy, isFalse);
    },
    skip: modelPath.isEmpty || !Platform.isWindows,
  );
}
