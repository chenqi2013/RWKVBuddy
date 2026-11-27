import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'agent_controller.dart';
import 'connection_settings.dart';
import 'trace_view.dart';
import 'team_chat.dart';
import 'team_builder.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

const ink = Color(0xFF252525);
const accent = Color(0xFF252525);
const muted = Color(0xFF8A8A8A);
const surface = Color(0xFFF7F7F7);
const line = Color(0xFFE8E8E8);

String taskDateLabel(String? timestamp, {DateTime? now}) {
  final created = DateTime.tryParse(timestamp ?? '')?.toLocal();
  if (created == null) return '';
  final current = (now ?? DateTime.now()).toLocal();
  final days = DateTime.utc(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime.utc(created.year, created.month, created.day)).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  return '$days天前';
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.controller});
  final AgentController? controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TECNO Buddy · 文件助手',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'PingFang SC',
      fontFamilyFallback: const ['Microsoft YaHei', 'Noto Sans CJK SC'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent,
        onPrimary: Colors.white,
        secondary: const Color(0xFF5D7067),
        surface: Colors.white,
        surfaceTint: Colors.transparent,
        outline: line,
      ),
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 5,
        shadowColor: const Color(0x18000000),
        menuPadding: const EdgeInsets.all(6),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: line),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 12,
          color: ink,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'PingFang SC',
            fontSize: 12,
            color: states.contains(WidgetState.disabled)
                ? const Color(0xFFB8B8B8)
                : ink,
          ),
        ),
        iconColor: const Color(0xFF666666),
        iconSize: 18,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x18000000),
        barrierColor: const Color(0x40000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: line),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13,
          height: 1.8,
          color: Color(0xFF727272),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFD5D5D5),
        dragHandleSize: Size(32, 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: ink, fontSize: 14, height: 1.7),
        bodyMedium: TextStyle(color: ink, fontSize: 13, height: 1.65),
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.6),
      ),
      dividerColor: line,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFF666666),
          hoverColor: const Color(0xFFF0F0F0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF646464),
          textStyle: const TextStyle(fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: const Color(0xFFECEEEE),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(color: ink, fontSize: 12),
      ),
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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB0B0B0)),
        ),
        hintStyle: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 14),
        contentPadding: const EdgeInsets.all(16),
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AgentController agent;
  final prompt = TextEditingController();
  final contentScroll = ScrollController(keepScrollOffset: false);
  String _lastRunId = '';
  bool _scrollQueued = false;
  bool _resetScrollPending = false;
  bool _followingLatest = false;
  late final Ticker _followTicker;
  Duration _lastFollowTick = Duration.zero;
  bool _exiting = false;
  bool _sidebarOpen = true;
  String? _hoveredHistoryId;
  String? _historyMenuId;
  int _category = 0;
  final promptFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    agent = widget.controller ?? AgentController();
    _lastRunId = agent.runId;
    _followingLatest = agent.busy;
    _followTicker = createTicker(_advanceFollowScroll);
    agent.addListener(_followConversation);
    WidgetsBinding.instance.addObserver(this);
    _queueFollowScroll();
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
    promptFocus.dispose();
    prompt.dispose();
    _followTicker.dispose();
    contentScroll.dispose();
    super.dispose();
  }

  void _followConversation() {
    final changed = agent.runId != _lastRunId;
    _lastRunId = agent.runId;
    if (changed) {
      _followTicker.stop();
      _followingLatest = agent.busy;
      _resetScrollPending = true;
    }
    _queueFollowScroll();
  }

  void _queueFollowScroll() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!mounted || !contentScroll.hasClients) return;
      if (_resetScrollPending) {
        _resetScrollPending = false;
        contentScroll.jumpTo(0);
      }
      if (_followingLatest &&
          !_followTicker.isActive &&
          contentScroll.position.extentAfter > 0.5) {
        _lastFollowTick = Duration.zero;
        _followTicker.start();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _advanceFollowScroll(Duration elapsed) {
    if (!_followingLatest || !contentScroll.hasClients) {
      _followTicker.stop();
      return;
    }
    final position = contentScroll.position;
    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining <= 0.5) {
      if (remaining > 0) contentScroll.jumpTo(position.maxScrollExtent);
      _followTicker.stop();
      return;
    }
    final milliseconds = _lastFollowTick == Duration.zero
        ? 16.0
        : (elapsed - _lastFollowTick).inMicroseconds / 1000;
    _lastFollowTick = elapsed;
    final fraction = (milliseconds / 80).clamp(0.01, 0.4);
    contentScroll.jumpTo(position.pixels + remaining * fraction);
  }

  bool _onConversationScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final direction = notification is UserScrollNotification
        ? notification.direction
        : notification is ScrollUpdateNotification
        ? contentScroll.position.userScrollDirection
        : null;
    if (direction == null) return false;
    if (direction == ScrollDirection.forward) {
      _followingLatest = false;
      _followTicker.stop();
    } else if (notification is UserScrollNotification ||
        direction == ScrollDirection.reverse) {
      _followingLatest = notification.metrics.extentAfter <= 24;
      if (_followingLatest) _queueFollowScroll();
    }
    return false;
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
      suggestedName: 'TECNO Buddy-分析报告.md',
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

  Future<void> exportFile(Json file, String runId) async {
    final name = file['name'] as String;
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: '成果文件', extensions: [name.split('.').last]),
      ],
    );
    if (location != null) {
      agent.send({
        'type': 'export.file',
        'runId': runId,
        'fileId': file['id'],
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
        final sidebar = constraints.maxWidth >= 880 && _sidebarOpen;
        return Scaffold(
          body: Row(
            children: [
              if (sidebar) SizedBox(width: 248, child: _sidebar()),
              Expanded(
                child: Column(
                  children: [
                    _header(sidebar),
                    if (agent.error.isNotEmpty) _message(agent.error, true),
                    if (agent.notice.isNotEmpty) _message(agent.notice, false),
                    Expanded(
                      child: agent.run == null ? _welcome() : _taskWorkspace(),
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

  void _newTask() {
    agent.newTask();
    prompt.clear();
    promptFocus.requestFocus();
  }

  Future<void> _newGroup() async {
    final team = await showTeamBuilder(context, agent, create: true);
    if (!mounted || team == null) return;
    _newTask();
    agent.configureTeam(true, team);
  }

  Widget _createButton(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onPressed,
  ) => TextButton.icon(
    onPressed: agent.busy ? null : onPressed,
    icon: Icon(icon, size: 15),
    label: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ),
    style: TextButton.styleFrom(
      foregroundColor: ink,
      backgroundColor: selected ? const Color(0xFFEAEAEA) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: selected ? Colors.transparent : line),
      ),
    ),
  );

  Widget _sidebar() => Container(
    decoration: const BoxDecoration(
      color: surface,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 21, 13, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'TECNO Buddy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: '收起侧栏',
                onPressed: () => setState(() => _sidebarOpen = false),
                icon: const Icon(Icons.space_dashboard_outlined, size: 18),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _createButton(
                '新建任务',
                Icons.add_circle_outline_rounded,
                !agent.groupChat,
                _newTask,
              ),
              const SizedBox(height: 6),
              _createButton(
                '新建群聊',
                Icons.group_add_outlined,
                agent.groupChat,
                _newGroup,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(25, 15, 20, 12),
          child: Text('最近任务', style: TextStyle(color: muted, fontSize: 11)),
        ),
        Expanded(
          child: agent.history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(22, 45, 22, 0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 24,
                        color: Color(0xFFC4C4C4),
                      ),
                      SizedBox(height: 13),
                      Text(
                        '从一个想法开始',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '你的任务会保存在这里',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: agent.history.length,
                  itemBuilder: (_, index) {
                    final item = agent.history[index];
                    final id = item['id'] as String;
                    return Padding(
                      key: ValueKey('history-item-$id'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoveredHistoryId = id),
                        onExit: (_) => setState(() => _hoveredHistoryId = null),
                        child: Material(
                          color: item['id'] == agent.runId
                              ? const Color(0xFFEAEAEA)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: agent.busy
                                ? null
                                : () => agent.load(item['id'] as String),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if ((item['teamName'] as String? ?? '')
                                            .isNotEmpty)
                                          Text(
                                            '群聊 · ${item['teamName']}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: muted,
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item['question'] as String,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.6,
                                                ),
                                              ),
                                            ),
                                            if (item['pinned'] == true)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  left: 4,
                                                ),
                                                child: Icon(
                                                  Icons.push_pin_outlined,
                                                  size: 12,
                                                  color: muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 44,
                                    height: 28,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child:
                                          _hoveredHistoryId == id ||
                                              _historyMenuId == id ||
                                              agent.runId == id
                                          ? SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: _historyMenu(item),
                                            )
                                          : Text(
                                              taskDateLabel(
                                                item['createdAt'] as String?,
                                              ),
                                              key: ValueKey('history-date-$id'),
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                color: muted,
                                                fontSize: 10,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 12, 14, 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E9E6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  size: 17,
                  color: Color(0xFF52675A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我的工作空间',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 5,
                          color: agent.connected
                              ? const Color(0xFF779783)
                              : const Color(0xFFC89863),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          agent.connected ? '服务已连接' : '服务未连接',
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '模型服务',
                onPressed: agent.busy ? null : _settings,
                icon: const Icon(Icons.settings_outlined, size: 18),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _header(bool sidebar) => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (!sidebar) ...[
            IconButton(
              tooltip: MediaQuery.sizeOf(context).width < 880 ? '任务记录' : '展开侧栏',
              onPressed: MediaQuery.sizeOf(context).width < 880
                  ? (agent.busy ? null : _showHistory)
                  : () => setState(() => _sidebarOpen = true),
              icon: const Icon(Icons.space_dashboard_outlined, size: 19),
            ),
            const SizedBox(width: 4),
          ],
          if (agent.run != null)
            Expanded(
              child: Text(
                agent.run!['team'] is Map
                    ? '${agent.run!['team']['name']} · ${(agent.run!['team']['members'] as List).length + 1} 位成员'
                    : agent.run!['question'] as String? ?? '文件助手',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF626262)),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    ),
  );

  Widget _taskWorkspace() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            Expanded(child: _runContent()),
            const SizedBox(height: 8),
            _composer(),
            _footnote(),
          ],
        ),
      ),
    ),
  );

  Widget _footnote() => const Padding(
    padding: EdgeInsets.only(top: 11, bottom: 14),
    child: Text(
      '内容由 AI 生成，请核实重要信息',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, color: Color(0xFFB4B4B4)),
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
  static const _categories = [
    (Icons.edit_note_rounded, '文档处理', '对比这些文档，整理主要差异和风险，并生成一份 Word 报告。'),
    (Icons.bar_chart_rounded, '数据分析', '分析这些表格中的关键数据、变化趋势和异常，整理结论。'),
    (Icons.code_rounded, '代码研究', '这是一个什么工程？请分析它的功能、技术栈和目录结构。'),
    (Icons.summarize_outlined, '内容总结', '总结这些资料的关键内容，提炼结论和待办事项。'),
    (Icons.note_add_outlined, '生成报告', '根据这些资料生成一份结构清晰、包含结论和建议的 Word 报告。'),
  ];
  static const _suggestions = [
    [
      ('对比两份合同，找出差异与风险', '请对比这两份合同，逐项列出差异、风险和修改建议。', false),
      ('提取文档中的关键信息', '请提取这些文档中的关键条款、金额、日期和责任方，并注明来源。', false),
      ('润色文档并生成新副本', '请润色这份文档，保留原意，改善表达，并生成一份 Word 新副本。', false),
    ],
    [
      ('分析表格中的趋势与异常', '请分析这些表格中的关键指标、变化趋势和异常数据，并注明分析依据。', false),
      ('汇总多份表格的关键指标', '请汇总这些表格的关键指标，说明统计口径和缺失数据，并生成汇总表。', false),
      ('经营与资金分析', '分析三家公司的经营与资金情况，指出异常并给我一份报告。', true),
    ],
    [
      ('这个工程用了哪些技术栈？', '这是一个什么工程？请分析它的功能、技术栈和目录结构。', false),
      ('梳理项目入口与核心模块', '请读取项目说明、依赖清单和入口代码，梳理启动流程与核心模块。', false),
      ('查找某项功能的实现位置', '请根据项目代码定位主要功能的实现文件，说明调用关系并引用实际读取的代码。', false),
    ],
    [
      ('总结资料中的关键结论', '请总结这些资料的关键内容，提炼主要结论，并注明来源。', false),
      ('从会议记录中提取待办', '请从会议记录中提取决议、待办事项、负责人和截止时间，未提供的信息请标明。', false),
      ('归纳多份资料的共识与分歧', '请归纳这些资料的共同观点、主要分歧和待确认的问题，并注明来源。', false),
    ],
    [
      ('把这些资料整理成一份报告', '根据这些资料生成一份结构清晰、包含结论和建议的 Word 报告。', false),
      ('整理本周进展与下周计划', '请根据这些资料整理本周完成事项、当前问题和下周计划，并生成周报 Word 文档。', false),
      ('生成项目分析报告', '请结合项目说明和实际代码，整理功能、技术栈、目录结构与待确认问题，生成项目分析 Word 报告。', false),
    ],
  ];

  void _fillPrompt(String text) {
    prompt.text = text;
    promptFocus.requestFocus();
  }

  Widget _welcome() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650 || constraints.maxHeight < 650;
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(24, compact ? 28 : 72, 24, 66),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          agent.groupChat
                              ? agent.team['name'] as String
                              : 'TECNO Buddy，我帮你',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 27 : 32,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1.1,
                          ),
                        ),
                        SizedBox(height: compact ? 30 : 42),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < _categories.length; i++)
                              _categoryChip(i),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _composer(home: true),
                        SizedBox(height: compact ? 25 : 38),
                        const Padding(
                          padding: EdgeInsets.only(left: 2, bottom: 12),
                          child: Text(
                            '试试这样开始',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final suggestion in _suggestions[_category])
                              _suggestion(
                                suggestion.$1,
                                suggestion.$2,
                                sample: suggestion.$3,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _footnote(),
        ],
      );
    },
  );

  Widget _categoryChip(int index) {
    final item = _categories[index];
    final selected = _category == index;
    return Material(
      color: selected ? ink : const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? ink : line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() => _category = index);
          _fillPrompt(item.$3);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.$1,
                size: 15,
                color: selected ? Colors.white : const Color(0xFF656565),
              ),
              const SizedBox(width: 6),
              Text(
                item.$2,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestion(String label, String text, {bool sample = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              if (sample) agent.useSample();
              _fillPrompt(text);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                  const Icon(Icons.north_east_rounded, size: 13),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _composer({bool home = false}) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (agent.groupChat)
          TeamControls(
            agent: agent,
            onMention: (name) {
              prompt.text =
                  '@$name ${prompt.text.replaceFirst(RegExp(r"^@[^ ]+ ?"), "")}';
              prompt.selection = TextSelection.collapsed(
                offset: prompt.text.length,
              );
              promptFocus.requestFocus();
            },
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E2E2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .025),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(17, 9, 13, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (agent.sourceMode == 'files' && agent.selectedFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 72),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: agent.selectedFiles
                            .map(
                              (path) => Tooltip(
                                message: path,
                                child: InputChip(
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 170,
                                    ),
                                    child: Text(
                                      path.split(RegExp(r'[/\\]')).last,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  avatar: const Icon(
                                    Icons.insert_drive_file_outlined,
                                    size: 15,
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
              Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter, control: true):
                      ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.enter, meta: true):
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
                    focusNode: promptFocus,
                    enabled: true,
                    minLines: home ? 3 : 1,
                    maxLines: home ? 5 : 3,
                    style: const TextStyle(fontSize: 14, height: 1.8),
                    decoration: InputDecoration(
                      hintText: agent.groupChat
                          ? '向专家团提问，或 @成员名 单独交流…'
                          : home
                          ? '今天帮你做些什么？添加文件，或直接说说你的想法…'
                          : '继续提问，或告诉我需要怎样修改…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: agent.busy ? null : _settings,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              agent.mode == 'local' || agent.usesLocalModel
                                  ? Icons.computer_outlined
                                  : Icons.language_rounded,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                agent.connectionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  if (agent.busy)
                    IconButton.filled(
                      tooltip: '停止任务',
                      onPressed: agent.cancel,
                      style: IconButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(34, 34),
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                    )
                  else
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: prompt,
                      builder: (context, value, _) => IconButton.filled(
                        key: const Key('send-message'),
                        tooltip: agent.run == null ? '开始处理' : '发送追问',
                        onPressed:
                            agent.connected && value.text.trim().isNotEmpty
                            ? submit
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: ink,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD8D8D8),
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size(34, 34),
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 2, 13, 4),
          child: Row(
            children: [
              if (agent.groupChat)
                TextButton.icon(
                  key: const Key('group-add-files'),
                  onPressed: agent.busy ? null : chooseFiles,
                  icon: const Icon(Icons.attach_file, size: 14),
                  label: const Text('添加文件', style: TextStyle(fontSize: 11)),
                ),
              Flexible(
                child: TextButton.icon(
                  onPressed: agent.busy ? null : chooseDirectory,
                  icon: const Icon(Icons.folder_open_outlined, size: 14),
                  label: Text(
                    agent.sourceMode == 'directory' &&
                            agent.workspace.isNotEmpty
                        ? agent.workspace.split(RegExp(r'[/\\]')).last
                        : '选择目录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '资料选项',
                enabled: !agent.busy,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 145),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    value: 'files',
                    child: Text('添加文件'),
                  ),
                  const PopupMenuItem(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    value: 'directory',
                    child: Text('选择目录'),
                  ),
                  const PopupMenuItem(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    value: 'sample',
                    child: Text('内置样例'),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'files') {
                    chooseFiles();
                  } else if (value == 'directory') {
                    chooseDirectory();
                  } else {
                    agent.useSample();
                  }
                },
              ),
              Expanded(
                child: Text(
                  agent.sourceMode == 'files' && agent.selectedFiles.isNotEmpty
                      ? '${agent.selectedFiles.length} 个附件'
                      : agent.run != null
                      ? '复用本轮资料'
                      : '',
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _runContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Text(
              agent.run!['template'] as String? ?? '正在准备任务',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (agent.run!['status'] == 'running' &&
              (agent.run!['mode'] == 'rwkv' ||
                  agent.traces.any((trace) => trace['kind'] == 'model'))) ...[
            Tooltip(
              message: agent.generationSpeed?['source'] == 'estimated'
                  ? '接口暂未返回 token 数，此值为估算；收到实际用量后更新。'
                  : '最近一次模型请求的平均生成速度，不含排队和等待首个 token 的时间。',
              child: Text(
                agent.generationSpeed?['tokensPerSecond'] is num
                    ? '${agent.generationSpeed?['source'] == 'estimated' ? '≈ ' : ''}${(agent.generationSpeed!['tokensPerSecond'] as num).toStringAsFixed(1)} tokens/s'
                    : '-- tokens/s',
                key: const Key('generation-speed'),
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (agent.busy) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Color(0xFF96A69A),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _tag(
            statusLabel(agent.run!['status'] as String?),
            _statusColor(agent.run!['status'] as String?),
          ),
          IconButton(
            tooltip: '跳到最新内容',
            onPressed: () {
              _followingLatest = true;
              _queueFollowScroll();
            },
            icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _queueFollowScroll();
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onConversationScroll,
            child: SingleChildScrollView(
              controller: contentScroll,
              key: ValueKey(agent.runId),
              child: Column(
                children: [_conversation(), const SizedBox(height: 18)],
              ),
            ),
          ),
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
            constraints: const BoxConstraints(maxWidth: 620),
            margin: const EdgeInsets.only(bottom: 14, top: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              turn['question'] as String? ?? '',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (turn['team'] is Map)
          TeamConversation(
            agent: agent,
            turn: turn,
            files: (turn['deliverables'] as List? ?? []).isNotEmpty
                ? _deliveryCards(turn)
                : null,
            trace: TraceView(
              agent: agent,
              turn: turn,
              onExport: exportTrace,
              showAnswerDraft: false,
            ),
            onExport: turn['id'] == agent.runId && agent.report.isNotEmpty
                ? exportReport
                : null,
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                    Icon(
                      Icons.auto_awesome_outlined,
                      color: Color(0xFF56685C),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'TECNO Buddy',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (turn['id'] == agent.runId ||
                    (turn['traces'] as List? ?? []).isNotEmpty) ...[
                  TraceView(
                    agent: agent,
                    turn: turn,
                    onExport: exportTrace,
                    showAnswerDraft: false,
                  ),
                  const SizedBox(height: 14),
                ],
                if (_answerText(turn).isNotEmpty) ...[
                  Text(
                    (turn['answer'] as String? ?? '').isNotEmpty
                        ? '生成结果'
                        : turn['status'] == 'running'
                        ? '回答草稿 · 正在生成，尚未完成'
                        : '回答草稿 · 已中断，未作为结果提交',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  MarkdownBody(
                    data: _answerText(turn),
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          p: const TextStyle(
                            fontSize: 14,
                            height: 1.9,
                            color: ink,
                          ),
                          h1: const TextStyle(
                            fontSize: 24,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                          ),
                          h2: const TextStyle(
                            fontSize: 19,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                          ),
                          h3: const TextStyle(
                            fontSize: 16,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                          ),
                          code: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                            backgroundColor: surface,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          blockSpacing: 14,
                        ),
                  ),
                ],
                if (turn['status'] != 'running' &&
                    (turn['answer'] as String? ?? '').isEmpty)
                  Text(
                    turn['error'] as String? ??
                        statusLabel(turn['status'] as String?),
                    style: const TextStyle(color: muted),
                  ),
                if ((turn['deliverables'] as List? ?? []).isNotEmpty)
                  _deliveryCards(turn),
                if (turn['id'] == agent.runId) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (agent.report.isNotEmpty)
                        TextButton.icon(
                          onPressed: exportReport,
                          icon: const Icon(Icons.download_outlined, size: 16),
                          label: const Text('导出结果'),
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

  String _answerText(Json turn) {
    final answer = turn['answer'] as String? ?? '';
    if (answer.isNotEmpty) return answer;
    final traces = turn['id'] == agent.runId
        ? agent.traces
        : (turn['traces'] as List? ?? []).cast<Json>();
    for (final trace in traces.reversed) {
      final draft = trace['answerPreview'] as String? ?? '';
      if (draft.isNotEmpty) return draft;
    }
    return (turn['error'] as String? ?? '').isEmpty
        ? turn['report'] as String? ?? ''
        : '';
  }

  Widget _deliveryCards(Json turn) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '成果文件',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const Text(
          '已保存新副本，可下载或继续要求修改。',
          style: TextStyle(fontSize: 11, color: muted),
        ),
        for (final item in turn['deliverables'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.insert_drive_file_outlined,
              color: accent,
            ),
            title: Text(
              item['name'] as String,
              style: const TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              '${((item['bytes'] as num) / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(fontSize: 10),
            ),
            trailing: TextButton.icon(
              onPressed: () => exportFile(
                Map<String, dynamic>.from(item as Map),
                turn['id'] as String,
              ),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('下载'),
            ),
          ),
      ],
    ),
  );

  Future<void> exportTrace() async {
    final location = await getSaveLocation(
      suggestedName: 'TECNO Buddy-执行轨迹.json',
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
  Color _statusColor(String? status) => switch (status) {
    'verified' || 'completed' => const Color(0xFF23856D),
    'failed' || 'blocked' => const Color(0xFFCA624D),
    'running' || 'waiting_model' || 'waiting_tool' => accent,
    'partial' || 'interrupted' => const Color(0xFFA77824),
    _ => muted,
  };
  Future<void> _showHistory() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: agent,
      builder: (context, _) => ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建任务'),
            onTap: () {
              Navigator.pop(context);
              _newTask();
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('新建群聊'),
            onTap: () {
              Navigator.pop(context);
              _newGroup();
            },
          ),
          for (final item in agent.history)
            ListTile(
              title: Text(item['question'] as String),
              trailing: SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child:
                      agent.runId == item['id'] || _historyMenuId == item['id']
                      ? _historyMenu(item)
                      : Text(
                          taskDateLabel(item['createdAt'] as String?),
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                agent.load(item['id'] as String);
              },
            ),
        ],
      ),
    ),
  );
  Widget _historyMenu(Json item) {
    final id = item['id'] as String;
    final pinned = item['pinned'] == true;
    final running = agent.busy && id == agent.runId;
    return PopupMenuButton<String>(
      key: ValueKey('history-more-$id'),
      tooltip: '更多',
      constraints: const BoxConstraints.tightFor(width: 148),
      offset: const Offset(-120, 6),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz, size: 18),
      onOpened: () => setState(() => _historyMenuId = id),
      onCanceled: () => setState(() => _historyMenuId = null),
      onSelected: (action) {
        setState(() => _historyMenuId = null);
        if (action == 'pin') agent.pinRun(id, !pinned);
        if (action == 'delete') unawaited(_deleteHistory(item));
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 16),
              const SizedBox(width: 10),
              Text(pinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 9),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          enabled: !running,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 16,
                color: running ? muted : const Color(0xFFC84E40),
              ),
              const SizedBox(width: 10),
              Text(
                '删除',
                style: TextStyle(
                  color: running
                      ? const Color(0xFFB8B8B8)
                      : const Color(0xFFC84E40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteHistory(Json item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: Text('将删除“${item['question']}”的本地记录和生成文件，无法恢复。原始文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC84E40),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) agent.deleteRun(item['id'] as String);
  }

  Future<void> _settings() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .25),
      builder: (dialogContext) => Dialog(
        key: const Key('settings-dialog'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          key: const Key('settings-panel'),
          width: 800,
          height: 720,
          child: ConnectionSettings(
            agent: agent,
            onClose: () => Navigator.pop(dialogContext),
          ),
        ),
      ),
    );
  }
}
