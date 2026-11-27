import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'agent_controller.dart';
import 'windows_text_editing.dart';

const _memberColors = [
  Color(0xFF7667A0),
  Color(0xFF4D8575),
  Color(0xFFB38740),
  Color(0xFF547FA5),
];

class TeamControls extends StatelessWidget {
  const TeamControls({super.key, required this.agent, required this.onMention});
  final AgentController agent;
  final ValueChanged<String> onMention;

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => _TeamEditor(team: agent.team),
    );
    if (result != null) agent.configureTeam(true, result);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('单助手'),
          selected: !agent.groupChat,
          onSelected: agent.busy
              ? null
              : (_) => agent.configureTeam(false, agent.team),
        ),
        ChoiceChip(
          label: const Text('专家团群聊'),
          selected: agent.groupChat,
          avatar: const Icon(Icons.groups_outlined, size: 17),
          onSelected: agent.busy
              ? null
              : (_) => agent.configureTeam(true, agent.team),
        ),
        if (agent.groupChat) ...[
          TextButton.icon(
            onPressed: agent.busy ? null : () => _edit(context),
            icon: const Icon(Icons.tune, size: 16),
            label: Text(
              '${agent.team['name']} · ${(agent.team['members'] as List).length + 1}人',
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '@成员',
            enabled: !agent.busy,
            onSelected: onMention,
            icon: const Icon(Icons.alternate_email, size: 19),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '全体', child: Text('@全体')),
              for (final member in agent.team['members'] as List)
                PopupMenuItem(
                  value: member['name'] as String,
                  child: Text('@${member['name']}'),
                ),
              const PopupMenuItem(value: '主持人', child: Text('@主持人')),
            ],
          ),
        ],
      ],
    ),
  );
}

class _TeamEditor extends StatefulWidget {
  const _TeamEditor({required this.team});
  final Json team;
  @override
  State<_TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends State<_TeamEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final List<
    ({String id, TextEditingController name, TextEditingController prompt})
  >
  members;
  final retired = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.team['name'] as String);
    members = [
      for (final member in widget.team['members'] as List)
        (
          id: member['id'] as String,
          name: TextEditingController(text: member['name'] as String),
          prompt: TextEditingController(text: member['prompt'] as String),
        ),
    ];
  }

  @override
  void dispose() {
    name.dispose();
    for (final member in members) {
      member.name.dispose();
      member.prompt.dispose();
    }
    for (final controller in retired) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'name': name.text.trim(),
      'members': [
        for (final member in members)
          {
            'id': member.id,
            'name': member.name.text.trim(),
            'prompt': member.prompt.text.trim(),
          },
      ],
    });
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    isDense: true,
    fillColor: const Color(0xFFFAFAFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFA0A0A0)),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
    ),
  );

  Widget _memberCard(int index) {
    final member = members[index];
    final color = _memberColors[index % _memberColors.length];
    return Container(
      key: ValueKey(member.id),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '专家 ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '移除专家',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: members.length == 1
                    ? null
                    : () => setState(() {
                        members.remove(member);
                        retired.addAll([member.name, member.prompt]);
                      }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('专家名称'),
          WindowsTextEditing(
            controller: member.name,
            child: TextFormField(
              controller: member.name,
              maxLength: 20,
              style: const TextStyle(fontSize: 13),
              decoration: _decoration('例如：财务分析师'),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty || RegExp(r'[\s@，。！？、:：;；]').hasMatch(text)) {
                  return '请填写名称，不含空格或分隔标点';
                }
                if (text == '主持人' ||
                    text == '全体' ||
                    members
                            .where((item) => item.name.text.trim() == text)
                            .length >
                        1) {
                  return '请使用不重复的专家名称';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),
          _label('职责与擅长领域'),
          WindowsTextEditing(
            controller: member.prompt,
            child: TextFormField(
              controller: member.prompt,
              minLines: 3,
              maxLines: 3,
              maxLength: 1200,
              style: const TextStyle(fontSize: 12, height: 1.7),
              decoration: _decoration('描述这位专家需要关注的问题与分析角度…'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请填写专家职责' : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 800,
      height: 780,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 18, 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F3F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_outlined,
                    size: 22,
                    color: Color(0xFF56685C),
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '配置专家团队',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '为同一份资料，加入不同的专业视角',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A8A8A),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭团队配置',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF7F7F7),
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('团队名称'),
                      WindowsTextEditing(
                        controller: name,
                        child: TextFormField(
                          controller: name,
                          maxLength: 40,
                          style: const TextStyle(fontSize: 13),
                          decoration: _decoration(
                            '为你的专家团队起个名字',
                          ).copyWith(fillColor: Colors.white),
                          validator: (value) =>
                              (value ?? '').trim().isEmpty ? '请输入团队名称' : null,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Text(
                            '团队成员',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${members.length} / 6',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: members.length == 6
                                ? null
                                : () => setState(() {
                                    members.add((
                                      id: 'member_${DateTime.now().microsecondsSinceEpoch}',
                                      name: TextEditingController(),
                                      prompt: TextEditingController(),
                                    ));
                                  }),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('添加专家'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              minimumSize: const Size(0, 34),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = constraints.maxWidth >= 620
                              ? (constraints.maxWidth - 14) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              for (
                                var index = 0;
                                index < members.length;
                                index++
                              )
                                SizedBox(
                                  width: cardWidth,
                                  child: _memberCard(index),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.fact_check_outlined,
                              size: 18,
                              color: Color(0xFF7A7A7A),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '主持人 · 自动加入',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '专家按顺序分析本地资料，主持人最后核对分歧、整理结论。',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF8A8A8A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(minimumSize: const Size(72, 38)),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(108, 38),
                  ),
                  child: const Text('保存团队'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class TeamConversation extends StatelessWidget {
  const TeamConversation({
    super.key,
    required this.agent,
    required this.turn,
    required this.trace,
    this.files,
    this.onExport,
  });
  final AgentController agent;
  final Json turn;
  final Widget trace;
  final Widget? files;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final messages = (turn['messages'] as List? ?? []).cast<Json>();
    final records = turn['id'] == agent.runId
        ? agent.traces
        : (turn['traces'] as List? ?? []).cast<Json>();
    final team = turn['team'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.groups_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  team['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${(team['members'] as List).length + 1} 位成员',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final member in [
              ...team['members'] as List,
              {'id': 'host', 'name': '主持人'},
            ])
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  '${member['name']} · ${_memberStatus(member['id'] as String, messages)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        for (var index = 0; index < messages.length; index++)
          _message(context, messages[index], records, index),
        if (turn['status'] != 'running' &&
            (turn['error'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              turn['error'] as String,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('查看执行过程', style: TextStyle(fontSize: 12)),
          children: [trace],
        ),
        if (onExport != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('导出讨论记录'),
            ),
          ),
      ],
    );
  }

  String _memberStatus(String id, List<Json> messages) {
    final matches = messages.where((message) => message['roleId'] == id);
    if (matches.isEmpty) return turn['status'] == 'running' ? '等待发言' : '未参与';
    return matches.last['status'] == 'running'
        ? turn['status'] == 'running'
              ? '正在处理'
              : '已中断'
        : statusLabel(matches.last['status'] as String?);
  }

  Widget _message(
    BuildContext context,
    Json message,
    List<Json> records,
    int index,
  ) {
    final running =
        message['status'] == 'running' && turn['status'] == 'running';
    final models = records.where(
      (record) =>
          record['roleId'] == message['roleId'] && record['kind'] == 'model',
    );
    final latest = models.isEmpty ? <String, dynamic>{} : models.last;
    final content = message['content'] as String? ?? '';
    final draft = running ? latest['answerPreview'] as String? ?? '' : '';
    final roster = (turn['team'] as Map)['members'] as List;
    final memberIndex = roster.indexWhere(
      (member) => member['id'] == message['roleId'],
    );
    final color = message['roleId'] == 'host'
        ? const Color(0xFF4D8575)
        : _memberColors[(memberIndex < 0 ? index : memberIndex) %
              _memberColors.length];
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: .12),
            child: Text(
              (message['name'] as String).characters.first,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message['name'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      running
                          ? '正在发言'
                          : message['status'] == 'running'
                          ? '已中断'
                          : statusLabel(message['status'] as String?),
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 7),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (content.isNotEmpty || draft.isNotEmpty)
                        MarkdownBody(
                          data: content.isNotEmpty ? content : draft,
                          selectable: true,
                        ),
                      if (running) ...[
                        if (draft.isNotEmpty) const SizedBox(height: 10),
                        Text(
                          latest['progress'] as String? ?? '正在分析，等待模型返回…',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (draft.isNotEmpty)
                          const Text(
                            '生成中，尚未提交',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 1),
                      ],
                      if (message['error'] != null)
                        Text(
                          message['error'] as String,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (message['final'] == true) files ?? const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
