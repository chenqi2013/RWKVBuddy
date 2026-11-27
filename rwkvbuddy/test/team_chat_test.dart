import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/main.dart';
import 'package:rwkvbuddy/team_builder.dart';

class RecordingController extends AgentController {
  RecordingController() : super(autoConnect: false);
  Json? command;
  @override
  void send(Json command) {
    this.command = command;
  }
}

class GroupFilePicker extends FileSelectorPlatform {
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => [XFile('/资料/合同.docx'), XFile('/资料/预算.xlsx'), XFile('/资料/会议.txt')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Real fonts make the optional visual capture readable on the local Mac.
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (await font.exists()) {
      final fontBytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['PingFang SC', 'Roboto', 'Ahem']) {
        final loader = FontLoader(family);
        loader.addFont(Future.value(fontBytes));
        await loader.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  test('group chat requires a model and sends the configured team', () {
    final agent = RecordingController()..groupChat = true;
    addTearDown(agent.dispose);
    agent.start('请讨论方案');
    expect(agent.command, isNull);
    expect(agent.error, contains('需要模型'));
    agent.mode = 'rwkv';
    agent.start('请讨论方案');
    expect(agent.command?['team'], agent.team);
    expect(agent.command?['sourceMode'], 'text');
  });

  testWidgets(
    'group file button selects multiple local files and submits them with the team',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = GroupFilePicker();
      addTearDown(() => FileSelectorPlatform.instance = original);
      final agent = RecordingController()
        ..groupChat = true
        ..mode = 'rwkv';
      addTearDown(agent.dispose);
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(controller: agent));
      await tester.ensureVisible(find.byKey(const Key('group-add-files')));
      await tester.tap(find.byKey(const Key('group-add-files')));
      await tester.pumpAndSettle();
      expect(agent.selectedFiles.length, 3);
      for (final name in ['合同.docx', '预算.xlsx', '会议.txt']) {
        expect(find.text(name), findsOneWidget);
      }
      agent.start('请各专家分析这些资料并注明来源');
      expect(agent.command?['sourceMode'], 'files');
      expect(agent.command?['selectedFiles'], agent.selectedFiles);
      expect(agent.command?['team'], agent.team);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'team editor customizes the roster and mention menu inserts a valid address',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MyApp(controller: agent),
        ),
      );
      await tester.tap(find.text('专家团群聊'));
      await tester.pumpAndSettle();
      expect(agent.groupChat, isTrue);
      await tester.tap(find.text('创作与研发团队 · 5人'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await boundary.toImage(pixelRatio: 1);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/ui-screenshots/team-editor.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      tester.view.physicalSize = const Size(600, 720);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('保存团队').hitTestable(), findsOneWidget);
      await tester.enterText(find.byKey(const Key('group-name')), '新品发布团队');
      await tester.tap(find.text('保存团队'));
      await tester.pumpAndSettle();
      expect(agent.team['name'], '新品发布团队');
      await tester.tap(find.byTooltip('@成员'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('@研发'));
      await tester.pumpAndSettle();
      expect(find.text('@研发 '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [600.0, 1280.0]) {
    testWidgets('group messages, interruption and files render at width $width', (
      tester,
    ) async {
      final agent = AgentController(autoConnect: false)..groupChat = true;
      addTearDown(agent.dispose);
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      agent.run = {
        'id': 'group-history',
        'question': '帮我做一个新品推广方案，列出分工与交付物。',
        'status': 'completed',
        'team': agent.team,
        'template': '创作与研发团队 · 专家团群聊',
        'answer': '明确目标后分阶段推进。',
        'messages': [
          {
            'id': 'one',
            'roleId': 'strategy',
            'name': '策划',
            'content': '**建议先明确目标用户。**\n\n推广分为预热、发布、复盘三个阶段。',
            'status': 'completed',
          },
          {
            'id': 'two',
            'roleId': 'copywriter',
            'name': '文案',
            'content': '沿用策划的三个阶段，分别准备预告、发布介绍和案例总结。',
            'status': 'completed',
          },
          {
            'id': 'three',
            'roleId': 'host',
            'name': '主持人',
            'content': '汇总：先确定人群与预算，再制作内容，最后核验实施效果。',
            'status': 'completed',
            'final': true,
          },
        ],
        'deliverables': [
          {'id': 'file', 'name': '新品推广方案.docx', 'bytes': 2048},
        ],
      };
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MyApp(controller: agent),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('策划'), findsOneWidget);
      expect(find.text('文案'), findsOneWidget);
      expect(find.text('主持人'), findsOneWidget);
      expect(find.text('新品推广方案.docx'), findsOneWidget);
      expect(find.text('生成结果'), findsNothing);
      expect(tester.takeException(), isNull);
      if (width == 1280) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File('build/ui-screenshots/group-chat.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      // A saved run interrupted by app shutdown must not display a live spinner.
      agent.run!['status'] = 'interrupted';
      (agent.run!['messages'] as List).last['status'] = 'running';
      agent.update();
      await tester.pumpAndSettle();
      expect(find.text('主持人 · 已中断'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'sidebar creation supports presets, mode selection and preserves the current chat on cancel',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      agent.run = {
        'id': 'existing',
        'question': '当前本地文件分析',
        'answer': '已有结果',
        'status': 'completed',
      };
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MyApp(controller: agent),
        ),
      );
      await tester.tap(find.text('新建群聊'));
      await tester.pumpAndSettle();
      expect(agent.runId, 'existing');
      expect(find.text('自定义配置'), findsOneWidget);
      expect(find.text('已选成员（0）'), findsOneWidget);
      final create = find.widgetWithText(FilledButton, '创建群聊');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(agent.runId, 'existing');
      await tester.tap(find.text('新建群聊'));
      await tester.pumpAndSettle();
      Future<void> screenshot(String name) async {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File('build/ui-screenshots/$name.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await screenshot('create-group-custom');
      await tester.tap(find.text('选择预设团队'));
      await tester.pumpAndSettle();
      await screenshot('create-group-presets');
      await tester.tap(find.byKey(const Key('preset-多视角决策团队')));
      await tester.pumpAndSettle();
      expect(find.text('团队成员（4 人）'), findsOneWidget);
      await screenshot('create-group-preset-detail');
      await tester.tap(find.text('返回列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preset-合同审阅团队')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用该团队模板'));
      await tester.pumpAndSettle();
      expect(find.text('已选成员（3）'), findsOneWidget);
      expect(agent.runId, 'existing');
      await tester.tap(find.text('创建群聊').last);
      await tester.pumpAndSettle();
      expect(agent.run, isNull);
      expect(agent.groupChat, isTrue);
      expect(agent.team['name'], '合同审阅团队');
      expect(agent.team['speakingMode'], 'assigned');
      expect((agent.team['members'] as List).length, 3);
      expect(agent.expertLibrary.length, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'member selection searches, adds and edits custom experts and enforces the six-member limit',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Json>(
                  context: context,
                  builder: (_) => const TeamBuilder(),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-reader')));
      await tester.pumpAndSettle();
      expect(find.text('已选成员（1）'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expert-search')), '财务');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-finance')), findsOneWidget);
      expect(find.byKey(const Key('select-contract')), findsNothing);
      await tester.tap(find.byKey(const Key('select-finance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('expert-name')), '采购审核员');
      await tester.enterText(
        find.byKey(const Key('expert-prompt')),
        '核对采购合同和预算，注明来源。',
      );
      await tester.ensureVisible(find.text('添加到团队'));
      await tester.tap(find.text('添加到团队'));
      await tester.pumpAndSettle();
      expect(find.text('已选成员（3）'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑采购审核员'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('expert-prompt')),
        '核对金额、日期和验收条款。',
      );
      await tester.ensureVisible(find.text('保存专家'));
      await tester.tap(find.text('保存专家'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('移除资料整理员'));
      await tester.pumpAndSettle();
      expect(find.text('已选成员（2）'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expert-search')), '');
      await tester.pumpAndSettle();
      for (final id in ['reader', 'analyst', 'reviewer', 'contract', 'risk']) {
        final target = find.byKey(Key('select-$id'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(find.text('已选成员（6）'), findsOneWidget);
      expect(find.text('最多选择 6 位专家'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
