import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'agent_controller.dart';
import 'connection_settings.dart';
import 'trace_view.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

const ink = Color(0xFF202438);
const accent = Color(0xFF6155D9);
const muted = Color(0xFF767D90);
const surface = Color(0xFFF6F7FB);
const line = Color(0xFFE8EAF1);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.controller});
  final AgentController? controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RWKVBuddy · 专家协作',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      scaffoldBackgroundColor: surface,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, height: 1.6),
        bodySmall: TextStyle(color: muted, height: 1.5),
      ),
      dividerColor: line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    ),
    home: WorkspacePage(controller: controller),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.controller});
  final AgentController? controller;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  late final AgentController agent;
  final prompt = TextEditingController();
  final contentScroll = ScrollController(keepScrollOffset: false);
  String _lastRunId = '';
  String _lastTab = '';
  bool _scrollQueued = false;
  bool _exiting = false;
  @override
  void initState() {
    super.initState();
    agent = widget.controller ?? AgentController();
    agent.addListener(_followConversation);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!_exiting) {
      _exiting = true;
      await agent.shutdown();
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    agent.removeListener(_followConversation);
    if (widget.controller == null) agent.dispose();
    prompt.dispose();
    contentScroll.dispose();
    super.dispose();
  }

  void _followConversation() {
    final changed = agent.runId != _lastRunId || agent.tab != _lastTab;
    _lastRunId = agent.runId;
    _lastTab = agent.tab;
    if (agent.tab != 'chat' || _scrollQueued) return;
    if (!changed &&
        contentScroll.hasClients &&
        contentScroll.position.maxScrollExtent - contentScroll.offset > 100) {
      return;
    }
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (mounted && agent.tab == 'chat' && contentScroll.hasClients) {
        contentScroll.jumpTo(contentScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> chooseDirectory() async {
    final selected = await getDirectoryPath(confirmButtonText: '分析此目录');
    if (selected != null) agent.setWorkspace(selected);
  }

  Future<void> chooseFiles() async {
    try {
      final files = await openFiles(
        confirmButtonText: '添加到分析任务',
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '文档、表格与文本',
            extensions: [
              'pdf',
              'docx',
              'xlsx',
              'txt',
              'md',
              'csv',
              'tsv',
              'json',
              'jsonl',
              'yaml',
              'yml',
              'dart',
              'ts',
              'js',
              'mjs',
              'py',
              'toml',
            ],
          ),
        ],
      );
      if (mounted) agent.addFiles(files.map((file) => file.path));
    } catch (error) {
      agent.error = '无法选择文件：$error';
      agent.update();
    }
  }

  Future<void> exportReport() async {
    final location = await getSaveLocation(
      suggestedName: 'RWKVBuddy-分析报告.md',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown 报告', extensions: ['md']),
      ],
    );
    if (location != null) {
      agent.send({
        'type': 'export',
        'runId': agent.runId,
        'path': location.path,
      });
    }
  }

  void submit() {
    if (prompt.text.trim().isEmpty || !agent.connected || agent.busy) return;
    agent.start(prompt.text);
    if (agent.error.isEmpty) prompt.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: agent,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        final sidebar = constraints.maxWidth >= 880;
        return Scaffold(
          body: Row(
            children: [
              if (sidebar) SizedBox(width: 214, child: _sidebar()),
              Expanded(
                child: Column(
                  children: [
                    _header(sidebar),
                    if (agent.error.isNotEmpty) _message(agent.error, true),
                    if (agent.notice.isNotEmpty) _message(agent.notice, false),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 30 : 18,
                          20,
                          wide ? 28 : 18,
                          0,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: agent.run == null
                                  ? _welcome()
                                  : _runContent(),
                            ),
                            _composer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _sidebar() => Container(
    color: const Color(0xFF1E2235),
    padding: const EdgeInsets.fromLTRB(18, 27, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.hub_rounded, color: Color(0xFFB9B2FF), size: 29),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'RWKVBuddy',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 38, top: 3),
          child: Text(
            '你的专家协作空间',
            style: TextStyle(color: Color(0xFFA7ADC5), fontSize: 11),
          ),
        ),
        const SizedBox(height: 33),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: agent.busy
                ? null
                : () {
                    agent.newTask();
                    prompt.clear();
                  },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建任务'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          '最近的任务',
          style: TextStyle(color: Color(0xFF969EB9), fontSize: 11),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: agent.history.isEmpty
              ? const Text(
                  '完成的任务会保存在这里',
                  style: TextStyle(color: Color(0xFF969EB9), fontSize: 12),
                )
              : ListView.builder(
                  itemCount: agent.history.length,
                  itemBuilder: (_, index) {
                    final item = agent.history[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: item['id'] == agent.runId
                            ? const Color(0xFF34384F)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: agent.busy
                              ? null
                              : () => agent.load(item['id'] as String),
                          child: Padding(
                            padding: const EdgeInsets.all(11),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['question'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE2E5F0),
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  statusLabel(item['status'] as String?),
                                  style: const TextStyle(
                                    color: Color(0xFF969EB9),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(color: Color(0xFF373B50)),
        TextButton.icon(
          onPressed: agent.busy ? null : _settings,
          icon: const Icon(
            Icons.dns_outlined,
            color: Color(0xFFB9B2FF),
            size: 18,
          ),
          label: const Text('远端连接', style: TextStyle(color: Color(0xFFE2E5F0))),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 7,
              color: agent.connected
                  ? const Color(0xFF71D5B1)
                  : const Color(0xFFFFBB82),
            ),
            const SizedBox(width: 8),
            Text(
              agent.connected ? '本地执行服务已连接' : '本地服务未连接',
              style: const TextStyle(color: Color(0xFFB3BAD2), fontSize: 11),
            ),
          ],
        ),
        if (!agent.connected)
          TextButton(onPressed: agent.connect, child: const Text('重新连接')),
        const SizedBox(height: 6),
      ],
    ),
  );
  Widget _header(bool sidebar) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
    child: Row(
      children: [
        if (!sidebar) ...[
          const Icon(Icons.hub_rounded, color: accent),
          const SizedBox(width: 8),
        ],
        const Expanded(
          child: Text(
            '专家协作台',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (!sidebar)
          IconButton(
            tooltip: '任务记录',
            onPressed: agent.busy ? null : _showHistory,
            icon: const Icon(Icons.history, size: 21),
          ),
        Flexible(
          child: TextButton.icon(
            onPressed: agent.busy ? null : _settings,
            icon: Icon(
              agent.mode == 'local' ? Icons.computer : Icons.cloud_outlined,
              size: 17,
            ),
            label: Text(
              agent.connectionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '远端连接设置',
          onPressed: agent.busy ? null : _settings,
          icon: const Icon(Icons.tune, size: 21),
        ),
      ],
    ),
  );
  Widget _message(String text, bool isError) => Container(
    width: double.infinity,
    color: isError ? const Color(0xFFFFF0ED) : const Color(0xFFEDF8F3),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
    child: Row(
      children: [
        Icon(
          isError ? Icons.info_outline : Icons.check_circle_outline,
          size: 18,
          color: isError ? Colors.deepOrange : Colors.teal,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        if (!agent.connected)
          TextButton(onPressed: agent.connect, child: const Text('重新连接')),
        IconButton(
          tooltip: '收起提示',
          onPressed: () {
            agent.error = '';
            agent.notice = '';
            agent.update();
          },
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
  Widget _welcome() => ListView(
    children: [
      const SizedBox(height: 34),
      const Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFECE9FC),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.auto_awesome, size: 30, color: accent),
          ),
        ),
      ),
      const SizedBox(height: 23),
      const Text(
        '今天想分析什么？',
        style: TextStyle(
          color: ink,
          fontSize: 28,
          height: 1.45,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        '直接提问，或添加文档、表格和项目资料。\n专家并行分析、交叉复核，你可以随时展开每一步的输入和结果。',
        style: TextStyle(color: muted, fontSize: 13, height: 1.9),
      ),
      const SizedBox(height: 29),
      _example(
        Icons.analytics_outlined,
        '经营与资金分析',
        '分析三家公司的经营与资金情况，指出异常并给我一份报告。',
        sample: true,
      ),
      const SizedBox(height: 10),
      _example(
        Icons.folder_open_outlined,
        '研究一个工作区',
        '分析这个项目的结构、技术栈和潜在风险，整理一份有来源的报告。',
      ),
      const SizedBox(height: 20),
      Text(
        agent.mode == 'local'
            ? '当前使用本地规则与真实工具，无需模型凭据。切换到远端模型 可由模型分别担任各专家。'
            : '当前使用真实远端模型会话。请确认服务地址、协议和访问凭据后发起任务。',
        style: const TextStyle(color: muted, fontSize: 11, height: 1.7),
      ),
      const SizedBox(height: 20),
    ],
  );
  Widget _example(
    IconData icon,
    String title,
    String text, {
    bool sample = false,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () {
        if (sample) agent.useSample();
        prompt.text = text;
      },
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Icon(icon, size: 22, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.north_west, size: 16, color: muted),
          ],
        ),
      ),
    ),
  );
  Widget _composer() => Padding(
    padding: const EdgeInsets.only(top: 13, bottom: 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              agent.sourceMode == 'files'
                  ? Icons.attach_file
                  : Icons.folder_outlined,
              size: 15,
              color: muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: agent.sourceMode == 'files'
                    ? agent.selectedFiles.join('\n')
                    : agent.workspace,
                child: Text(
                  agent.sourceMode == 'files'
                      ? '已添加 ${agent.selectedFiles.length} 个文件'
                      : agent.workspace.isEmpty
                      ? '可直接提问，也可添加资料'
                      : agent.workspace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('add-files'),
              onPressed: agent.busy ? null : chooseFiles,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('添加文件', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: agent.busy ? null : chooseDirectory,
              child: const Text('选择目录', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: agent.busy ? null : agent.useSample,
              child: const Text('内置样例', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (agent.sourceMode == 'files' && agent.selectedFiles.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 76),
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: agent.selectedFiles
                      .map(
                        (path) => Tooltip(
                          message: path,
                          child: InputChip(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                path.split(RegExp(r'[/\\]')).last,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            avatar: const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 14,
                            ),
                            onDeleted: agent.busy
                                ? null
                                : () => agent.removeFile(path),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: line),
          ),
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
          child: Column(
            children: [
              Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter, control: true):
                      ActivateIntent(),
                },
                child: Actions(
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        submit();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: prompt,
                    enabled: true,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '输入问题或继续追问…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.groups_2_outlined, size: 17, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      agent.run == null ? '专家并行 · 结果复核' : '继续追问将复用本轮资料',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ),
                  if (agent.busy)
                    OutlinedButton.icon(
                      onPressed: agent.cancel,
                      icon: const Icon(Icons.stop_rounded, size: 17),
                      label: const Text('停止任务'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: agent.connected ? submit : null,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                      label: Text(agent.run == null ? '开始协作' : '发送追问'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'PDF / DOCX / XLSX / 文本 · 最多 20 个文件 · Ctrl + Enter 发送',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ),
      ],
    ),
  );

  Widget _runContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              agent.run!['template'] as String? ?? '正在准备任务',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _tag(
            statusLabel(agent.run!['status'] as String?),
            _statusColor(agent.run!['status'] as String?),
          ),
        ],
      ),
      if (agent.busy)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _inlineTeam(),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tab('chat', '对话', Icons.chat_bubble_outline),
            _tab('activity', '执行轨迹', Icons.timeline),
            _tab('report', '分析报告', Icons.description_outlined),
            _tab('expert', '专家成果', Icons.person_outline),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          controller: contentScroll,
          key: ValueKey('${agent.runId}-${agent.tab}'),
          children: [
            if (agent.tab == 'chat') _conversation(),
            if (agent.tab == 'activity')
              TraceView(agent: agent, onExport: exportTrace),
            if (agent.tab == 'report') _report(),
            if (agent.tab == 'expert') _expertDetail(),
            const SizedBox(height: 18),
          ],
        ),
      ),
    ],
  );

  Widget _conversation() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final turn in [...agent.turns, agent.run!]) ...[
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 740),
            margin: const EdgeInsets.only(bottom: 14, top: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECE9FC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              turn['question'] as String? ?? '',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(19),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hub_outlined, color: accent, size: 19),
                  SizedBox(width: 8),
                  Text(
                    'RWKVBuddy',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if ((turn['answer'] as String? ?? turn['report'] as String? ?? '')
                  .isNotEmpty)
                MarkdownBody(
                  data:
                      turn['answer'] as String? ??
                      turn['report'] as String? ??
                      '',
                  selectable: true,
                )
              else
                Text(
                  turn['status'] == 'running'
                      ? '正在分析资料并复核结果…'
                      : statusLabel(turn['status'] as String?),
                  style: const TextStyle(color: muted),
                ),
              if (turn['id'] == agent.runId) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => agent.setTab('activity'),
                      icon: const Icon(Icons.timeline, size: 16),
                      label: Text('查看 ${agent.traces.length} 个执行步骤'),
                    ),
                    if (agent.report.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => agent.setTab('report'),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('完整报告与来源'),
                      ),
                    if (agent.answer.isNotEmpty)
                      IconButton(
                        tooltip: '复制回答',
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: agent.answer),
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 16),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Future<void> exportTrace() async {
    final location = await getSaveLocation(
      suggestedName: 'RWKVBuddy-执行轨迹.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: '执行轨迹 JSON', extensions: ['json']),
      ],
    );
    if (location != null) {
      agent.send({
        'type': 'export.trace',
        'runId': agent.runId,
        'path': location.path,
      });
    }
  }

  Widget _tab(String id, String label, IconData icon) => TextButton.icon(
    onPressed: () => agent.setTab(id),
    icon: Icon(icon, size: 17),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: TextButton.styleFrom(
      foregroundColor: agent.tab == id ? accent : muted,
      backgroundColor: agent.tab == id
          ? const Color(0xFFECE9FC)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
    ),
  );

  Widget _report() {
    if (agent.report.isEmpty) {
      return _empty('专家交付并完成复核后，报告会出现在这里', Icons.description_outlined);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 5,
          children: [
            OutlinedButton.icon(
              onPressed: exportReport,
              icon: const Icon(Icons.file_download_outlined, size: 17),
              label: const Text('导出报告'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: agent.report));
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('报告已复制')));
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('复制'),
            ),
            if (Platform.isWindows)
              TextButton.icon(
                onPressed: () {
                  unawaited(
                    Process.run('explorer.exe', ['/select,', agent.reportPath]),
                  );
                },
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('所在文件夹'),
              ),
          ],
        ),
        const SizedBox(height: 15),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: MarkdownBody(data: agent.report, selectable: true),
        ),
      ],
    );
  }

  Widget _expertDetail() {
    final role = agent.roles.firstWhere(
      (r) => r['id'] == agent.selectedRole,
      orElse: () => agent.roles.first,
    );
    final artifact = agent.selectedArtifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          role['name'] as String,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          role['duty'] as String,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (artifact == null)
          _empty(
            agent.tasks[role['id']]?['detail'] as String? ?? '等待任务分配',
            Icons.person_outline,
          )
        else ...[
          _tag(
            '${artifact['source'] == 'rwkv' ? '远端模型' : '本地规则'} · v${artifact['version']}',
            accent,
          ),
          const SizedBox(height: 14),
          Text(artifact['analysis']['summary'] as String),
          const SizedBox(height: 15),
          for (final finding in artifact['analysis']['findings'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    finding['text'] as String,
                    style: const TextStyle(fontSize: 13, height: 1.8),
                  ),
                  const SizedBox(height: 7),
                  _tag(
                    '来源 ${(finding['evidenceIds'] as List).join(' · ')}',
                    muted,
                  ),
                ],
              ),
            ),
          if (artifact['toolVerified'] == true)
            const Text(
              '输入台账的数值字段已由本机工具核算',
              style: TextStyle(fontSize: 11, color: Color(0xFF23856D)),
            ),
        ],
      ],
    );
  }

  Widget _inlineTeam() => Row(
    spacing: 8,
    children: agent.roles
        .map(
          (role) => ActionChip(
            onPressed: () => agent.selectRole(role['id'] as String),
            avatar: Icon(
              _roleIcon(role['id'] as String),
              size: 15,
              color: accent,
            ),
            label: Text(
              '${role['name']} · ${statusLabel(agent.tasks[role['id']]?['status'] as String?)}',
              style: const TextStyle(fontSize: 10),
            ),
            backgroundColor: Colors.white,
            side: const BorderSide(color: line),
          ),
        )
        .toList(),
  );
  Widget _empty(String text, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFFA9AFC1)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    ),
  );
  Widget _tag(String text, Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    ),
  );
  IconData _roleIcon(String id) =>
      const {
        'coordinator': Icons.hub_outlined,
        'operations': Icons.analytics_outlined,
        'cash': Icons.account_balance_wallet_outlined,
        'risk': Icons.shield_outlined,
        'reviewer': Icons.fact_check_outlined,
      }[id] ??
      Icons.person_outline;
  Color _statusColor(String? status) => switch (status) {
    'verified' || 'completed' => const Color(0xFF23856D),
    'failed' || 'blocked' => const Color(0xFFCA624D),
    'running' || 'waiting_model' || 'waiting_tool' => accent,
    'partial' || 'interrupted' => const Color(0xFFA77824),
    _ => muted,
  };
  Future<void> _showHistory() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('新建任务'),
          onTap: () {
            Navigator.pop(context);
            agent.newTask();
          },
        ),
        for (final item in agent.history)
          ListTile(
            title: Text(item['question'] as String),
            subtitle: Text(statusLabel(item['status'] as String?)),
            onTap: () {
              Navigator.pop(context);
              agent.load(item['id'] as String);
            },
          ),
      ],
    ),
  );
  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ConnectionSettings(agent: agent)),
    );
  }
}
