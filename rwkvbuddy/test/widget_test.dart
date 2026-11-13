import 'package:flutter/material.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';
import 'package:rwkvbuddy/trace_view.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TestFilePicker extends FileSelectorPlatform {
  List<XFile> result = [];
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  test(
    'bundled Qwen profile is enabled once and subsequent mode choices are preserved',
    () async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      final profile = <String, dynamic>{
        'id': 'builtin-qwen-server',
        'version': 1,
        'name': '千问 · 服务器',
        'baseUrl': 'http://localhost:8000',
        'apiKey': 'test-key',
        'model': '',
        'protocol': 'chat',
      };
      await controller.installDefaultConnection(profile);
      expect(controller.mode, 'rwkv');
      expect(controller.activeConnectionId, 'builtin-qwen-server');
      expect(controller.config['apiKey'], 'test-key');
      controller.setMode('local');
      await controller.installDefaultConnection(profile);
      expect(controller.mode, 'local');
      expect(controller.connections.length, 1);
    },
  );
  testWidgets(
    'file generation can be selected and actual generated files remain downloadable in history',
    (tester) async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(controller: controller));
      await tester.tap(find.byKey(const Key('generate-files')));
      await tester.pump();
      expect(controller.generateFiles, isTrue);
      controller.run = {
        'id': 'history',
        'question': '修改文档',
        'status': 'completed',
        'answer': '已生成新副本。',
        'deliverables': [
          {'id': 'generated', 'name': '修改后的合同.docx', 'bytes': 4096},
        ],
      };
      controller.update();
      await tester.pump();
      expect(find.text('修改后的合同.docx'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file picker adds and deduplicates attachments; removal and cancellation preserve selection',
    (tester) async {
      final originalPicker = FileSelectorPlatform.instance;
      final picker = TestFilePicker()
        ..result = [XFile('C:/资料/合同.docx'), XFile('C:/数据/销售.xlsx')];
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = originalPicker);
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(600, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(controller: controller));
      await tester.tap(find.byKey(const Key('add-files')));
      await tester.pumpAndSettle();
      expect(controller.sourceMode, 'files');
      expect(controller.selectedFiles.length, 2);
      expect(find.text('合同.docx'), findsOneWidget);
      expect(find.text('销售.xlsx'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-files')));
      await tester.pumpAndSettle();
      expect(controller.selectedFiles.length, 2);
      picker.result = [];
      await tester.tap(find.byKey(const Key('add-files')));
      await tester.pumpAndSettle();
      expect(controller.selectedFiles.length, 2);
      await tester.tap(
        find
            .descendant(
              of: find.byType(InputChip).first,
              matching: find.byType(Icon),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(controller.selectedFiles, ['C:/数据/销售.xlsx']);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'an empty file selection never falls back to the previous directory',
    () {
      final controller = AgentController(autoConnect: false)
        ..workspace = 'previous-directory';
      addTearDown(controller.dispose);
      controller.addFiles(['C:/user.txt']);
      controller.removeFile('C:/user.txt');
      controller.start('分析这个文件');
      expect(controller.busy, isFalse);
      expect(controller.error, contains('请先添加文件'));
      controller.useSample();
      expect(controller.sourceMode, 'directory');
    },
  );
  testWidgets(
    'workspace is usable at desktop and narrow widths; example fills prompt',
    (tester) async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(controller: controller));
      expect(find.text('你的专家团队'), findsNothing);
      expect(find.text('开始处理'), findsOneWidget);
      await tester.tap(find.text('经营与资金分析'));
      await tester.pump();
      expect(find.text('分析三家公司的经营与资金情况，指出异常并给我一份报告。'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(600, 720);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed tool remains visible alongside partial results without role UI',
    (tester) async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      controller.run = {
        'id': 'example',
        'question': '处理合同',
        'status': 'partial',
        'answer': '已读取合同，成果文件生成失败。',
      };
      controller.traces = [
        {
          'id': 'failed',
          'kind': 'tool',
          'name': 'files.create',
          'status': 'failed',
          'error': '文件格式无效',
          'input': {'name': '合同.docx'},
        },
      ];
      await tester.pumpWidget(MyApp(controller: controller));
      expect(find.text('部分完成'), findsOneWidget);
      expect(find.text('生成成果文件'), findsOneWidget);
      expect(find.textContaining('文件格式无效'), findsOneWidget);
      expect(find.text('已读取合同，成果文件生成失败。'), findsOneWidget);
      for (final oldLabel in ['专家成果', '分析报告', '执行轨迹', '全部角色', '资金分析师']) {
        expect(find.text(oldLabel), findsNothing);
      }
      tester.view.physicalSize = const Size(600, 720);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connection editor validates URL and existing profiles can be activated',
    (tester) async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      controller.connections = [
        {
          'id': 'remote',
          'name': '办公室服务',
          'baseUrl': 'http://localhost:8000',
          'model': 'rwkv-test',
          'protocol': 'rwkv',
        },
      ];
      await tester.pumpWidget(MyApp(controller: controller));
      await tester.tap(find.byTooltip('远端连接设置'));
      await tester.pumpAndSettle();
      expect(find.text('办公室服务'), findsOneWidget);
      await tester.tap(find.text('使用此连接'));
      await tester.pumpAndSettle();
      expect(controller.mode, 'rwkv');
      expect(controller.config['model'], 'rwkv-test');
      await tester.tap(find.byTooltip('远端连接设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建连接').last);
      await tester.pumpAndSettle();
      final address = find.widgetWithText(TextField, '服务地址');
      await tester.enterText(address, 'file:///invalid');
      final button = find.text('测试连接 / 获取模型');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入完整的 HTTP(S) 服务地址'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'process shows file reads and actual tool details without roles or filters',
    (tester) async {
      final controller = AgentController(autoConnect: false);
      addTearDown(controller.dispose);
      controller.events = [
        {
          'type': 'input.file_started',
          'payload': {'name': '合同.txt'},
        },
        {
          'type': 'input.file_parsed',
          'payload': {'name': '合同.txt', 'lines': 12},
        },
      ];
      controller.traces = [
        {
          'id': 'tool',
          'roleId': 'cash',
          'kind': 'tool',
          'name': 'calculator',
          'status': 'completed',
          'startedAt': '2026-11-13T01:00:00Z',
          'finishedAt': '2026-11-13T01:00:01Z',
          'durationMs': 1000,
          'input': {'expression': '6*7'},
          'output': '{"result":42}',
        },
        {
          'id': 'model',
          'roleId': 'risk',
          'kind': 'model',
          'name': 'rwkv-test',
          'status': 'failed',
          'startedAt': '2026-11-13T01:00:00Z',
          'finishedAt': '2026-11-13T01:00:02Z',
          'durationMs': 2000,
          'input': {'question': '风险'},
          'error': 'HTTP 403',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [TraceView(agent: controller, onExport: () {})],
            ),
          ),
        ),
      );
      await tester.tap(find.text('计算数据'));
      await tester.pumpAndSettle();
      expect(find.textContaining('6*7'), findsOneWidget);
      expect(find.textContaining('42'), findsOneWidget);
      await tester.tap(find.text('计算数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分析与整理'));
      await tester.pumpAndSettle();
      expect(find.text('HTTP 403'), findsOneWidget);
      expect(find.text('合同.txt · 已读取 12 行'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('全部角色'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
