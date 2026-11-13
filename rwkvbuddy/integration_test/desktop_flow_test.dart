import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class IntegrationFilePicker extends FileSelectorPlatform {
  IntegrationFilePicker(this.files);
  final List<XFile> files;
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => files;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows app starts its bundled service and delivers a real multi-role report',
    (tester) async {
      // Keep the native Windows IME from overwriting injected test text.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final sessionRoot = await Directory.systemTemp.createTemp(
        'rwkvbuddy-ui-session-',
      );
      final agent = AgentController(
        serviceEnvironment: {'RWKVBUDDY_DATA_DIR': '${sessionRoot.path}/runs'},
      );
      final capture = GlobalKey();
      addTearDown(() async {
        await agent.shutdown();
        agent.dispose();
        expect(
          sessionRoot.parent.absolute.path,
          Directory.systemTemp.absolute.path,
        );
        expect(
          sessionRoot.path.split(Platform.pathSeparator).last,
          startsWith('rwkvbuddy-ui-session-'),
        );
        await sessionRoot.delete(recursive: true);
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MyApp(controller: agent),
        ),
      );
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 150 && !done(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue, reason: agent.error);
        await tester.pumpAndSettle();
      }

      Future<void> screenshot(String name) async {
        await tester.pump();
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ui-screenshots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await waitUntil(() => agent.connected);
      expect(agent.config['id'], 'builtin-qwen-server');
      expect(agent.config['protocol'], 'chat');
      expect(agent.config['apiKey'], isNotEmpty);
      expect(agent.mode, 'rwkv');
      agent.setMode('local');
      await screenshot('welcome');
      await tester.tap(find.text('经营与资金分析'));
      await tester.pump();
      await tester.tap(find.text('开始协作'));
      await waitUntil(() => agent.run != null && !agent.busy);
      expect(agent.run!['status'], 'completed');
      expect(agent.artifacts.length, 3);
      expect(agent.report, contains('1,070,150.00'));
      expect(agent.report, contains('56,900.25'));
      expect(agent.tasks['reviewer']!['status'], 'verified');
      await screenshot('completed-report');
      await tester.tap(find.text('执行轨迹'));
      await tester.pump();
      expect(
        agent.events.where((e) => e['type'] == 'artifact.created').length,
        3,
      );
      await screenshot('collaboration');
      final temp = await Directory.systemTemp.createTemp('rwkvbuddy-ui-files-');
      final originalPicker = FileSelectorPlatform.instance;
      addTearDown(() async {
        FileSelectorPlatform.instance = originalPicker;
        expect(temp.parent.absolute.path, Directory.systemTemp.absolute.path);
        expect(
          temp.path.split(Platform.pathSeparator).last,
          startsWith('rwkvbuddy-ui-files-'),
        );
        await temp.delete(recursive: true);
      });
      final note = File('${temp.path}/客户需求.txt');
      final table = File('${temp.path}/销售.csv');
      await note.writeAsString('客户要求：预算 24680 元，2026年12月交付。\n风险：合同尚未签署。');
      await table.writeAsString('产品,收入,成本\n设备A,13579,4321\n');
      FileSelectorPlatform.instance = IntegrationFilePicker([
        XFile(note.path),
        XFile(table.path),
      ]);
      agent.newTask();
      await tester.pump();
      await tester.tap(find.byKey(const Key('add-files')));
      await tester.pump();
      expect(agent.selectedFiles.length, 2);
      expect(find.text('客户需求.txt'), findsOneWidget);
      final input = find.byType(TextField).first;
      await tester.enterText(input, '分析我添加的客户需求和销售数据，指出风险。');
      await screenshot('selected-files');
      await tester.tap(find.text('开始协作'));
      await waitUntil(() => agent.run != null && !agent.busy);
      expect(agent.run!['status'], 'completed', reason: agent.error);
      expect(agent.report, contains('24680'));
      expect(agent.report, contains('13579'));
      expect(agent.report, isNot(contains('北辰科技')));
      expect((agent.run!['attachments'] as List).length, 2);
      await screenshot('uploaded-report');
      final uploadedId = agent.runId;
      agent.newTask();
      agent.load(uploadedId);
      await waitUntil(() => agent.runId == uploadedId);
      expect(agent.sourceMode, 'files');
      expect(agent.selectedFiles.length, 2);
      expect(agent.traces, isNotEmpty);
      await note.delete();
      await table.delete();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isTrue,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '继续说明资料中存在的风险');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '继续说明资料中存在的风险',
      );
      await tester.tap(find.text('发送追问'));
      await tester.pump();
      await waitUntil(
        () => agent.run != null && agent.runId != uploadedId && !agent.busy,
      );
      expect(agent.run!['status'], 'completed', reason: agent.error);
      expect(agent.run!['parentRunId'], uploadedId);
      expect(agent.report, contains('24680'));
      expect(agent.turns.length, 1);
      await screenshot('followup');
      await tester.tap(find.byTooltip('远端连接设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建连接').last);
      await tester.pumpAndSettle();
      await screenshot('connection-settings');
      await tester.pageBack();
      await tester.pumpAndSettle();
      final storageAgent = AgentController(autoConnect: false)
        ..dataRoot = '${temp.path}/runs';
      final profileId = 'ui-smoke-${DateTime.now().microsecondsSinceEpoch}';
      try {
        await storageAgent.saveConnection({
          'id': profileId,
          'name': '验证连接',
          'baseUrl': 'http://localhost:8000',
          'model': 'test',
          'protocol': 'chat',
          'apiKey': 'smoke-private-token',
          'headers': {'X-Private': 'smoke-private-header'},
        });
        final publicFile = await File(
          '${temp.path}/settings.json',
        ).readAsString();
        expect(publicFile, isNot(contains('smoke-private-token')));
        expect(publicFile, isNot(contains('smoke-private-header')));
        final secret = await const FlutterSecureStorage().read(
          key: 'rwkvbuddy.connection.$profileId',
        );
        expect(jsonDecode(secret!)['apiKey'], 'smoke-private-token');
      } finally {
        await storageAgent.deleteConnection(profileId);
        storageAgent.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
