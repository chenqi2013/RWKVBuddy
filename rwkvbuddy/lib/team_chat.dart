import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'agent_controller.dart';
import 'team_builder.dart';

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
    final result = await showTeamBuilder(context, agent);
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
                '${speakingModeLabel(team['speakingMode'] as String? ?? 'sequential')} · ${(team['members'] as List).length + 1} 位成员',
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
        if ((turn['tasks'] as Map? ?? {}).isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '主持人 · 本轮分工',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final task in (turn['tasks'] as Map).values)
                  Text(
                    '${task['name']}：${task['task']}',
                    style: const TextStyle(fontSize: 12, height: 1.8),
                  ),
              ],
            ),
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
    final tasks = turn['tasks'] as Map? ?? {};
    if (matches.isEmpty &&
        (turn['team'] as Map)['speakingMode'] == 'assigned') {
      if (id != 'host' && tasks.isNotEmpty && !tasks.containsKey(id)) {
        return '未分配';
      }
      if (id == 'host' && tasks.isEmpty && turn['status'] == 'running') {
        return '正在分工';
      }
    }
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
