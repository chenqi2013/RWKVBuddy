import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/trace_view.dart';

void main() {
  testWidgets('format recovery is shown separately from token truncation', (
    tester,
  ) async {
    final agent = AgentController(autoConnect: false);
    addTearDown(agent.dispose);
    agent.traces = [
      {
        'id': 'json-retry',
        'kind': 'model',
        'name': 'test-model',
        'status': 'completed',
        'input': {'question': '你是哪一家模型？', 'jsonRecovery': true},
        'output': '{"answer":"公开回答"}',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [TraceView(agent: agent, onExport: () {})],
          ),
        ),
      ),
    );
    expect(find.text('返回格式不符合要求，已启用 JSON 输出模式重新请求'), findsOneWidget);
    expect(find.textContaining('输出超限后重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file reads render Markdown and retain exact raw text and JSON', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final agent = AgentController(autoConnect: false);
    addTearDown(agent.dispose);
    const content =
        '# 工程介绍\n\n支持 **文件分析** 与 `read_file`。\n\n'
        '| 模块 | 技术 |\n| --- | --- |\n| 界面 | Flutter |\n\n'
        '```text\napp/\n  src/\n```\n';
    agent.traces = [
      {
        'id': 'read-md',
        'kind': 'tool',
        'name': 'read_file',
        'status': 'completed',
        'input': {'path': 'README.MD'},
        'output': jsonEncode({
          'path': 'README.MD',
          'startLine': 1,
          'endLine': 12,
          'text': content,
        }),
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [TraceView(agent: agent, onExport: () {})],
          ),
        ),
      ),
    );
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('工程介绍'), findsOneWidget);
    expect(find.text(content), findsNothing);
    await tester.tap(find.byKey(const ValueKey('source-read-md')));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.text(content), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('details-read-md')));
    await tester.pumpAndSettle();
    expect(find.text('文件正文'), findsOneWidget);
    expect(find.text('原始输出'), findsNothing);
    final raw = find.byKey(const ValueKey('raw-output-read-md'));
    await tester.ensureVisible(raw);
    await tester.tap(raw);
    await tester.pumpAndSettle();
    expect(find.text('原始输出'), findsOneWidget);
    expect(find.textContaining('"text": "# 工程介绍\\n'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source code stays literal while public progress and drafts render Markdown',
    (tester) async {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      agent.traces = [
        {
          'id': 'code',
          'kind': 'tool',
          'name': 'read_file',
          'status': 'completed',
          'input': {'path': 'main.py'},
          'output': jsonEncode({
            'path': 'main.py',
            'text': '# heading\nvalue = "**literal**"',
          }),
        },
        {
          'id': 'model',
          'kind': 'model',
          'name': 'qwen',
          'status': 'running',
          'input': {'project': {}},
          'progress': '正在读取 **说明文档**。',
          'answerPreview': '## 项目功能\n\n- 文件分析\n- 成果导出',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [TraceView(agent: agent, onExport: () {})],
            ),
          ),
        ),
      );
      expect(find.text('# heading\nvalue = "**literal**"'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNWidgets(2));
      expect(find.text('项目功能'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
