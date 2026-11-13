import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'agent_controller.dart';

class TraceView extends StatefulWidget {
  const TraceView({super.key, required this.agent, required this.onExport});
  final AgentController agent;
  final VoidCallback onExport;
  @override
  State<TraceView> createState() => _TraceViewState();
}

class _TraceViewState extends State<TraceView> {
  String role = 'all';
  String filter = 'all';
  String format(dynamic value) {
    if (value is String) {
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
      } catch (_) {
        return value;
      }
    }
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  String author(String? id) =>
      widget.agent.roles.where((item) => item['id'] == id).firstOrNull?['name']
          as String? ??
      '协调员';
  Color color(String? status) => status == 'failed'
      ? Colors.deepOrange
      : status == 'cancelled'
      ? Colors.grey
      : status == 'running'
      ? const Color(0xFF6155D9)
      : Colors.teal;
  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final traces = agent.traces
        .where(
          (item) =>
              (role == 'all' || item['roleId'] == role) &&
              (filter == 'all' ||
                  filter == item['kind'] ||
                  filter == item['status']),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${agent.traces.length} 个执行步骤',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: role,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: '角色',
                  contentPadding: EdgeInsets.all(10),
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部角色')),
                  ...agent.roles.map(
                    (item) => DropdownMenuItem(
                      value: item['id'] as String,
                      child: Text(item['name'] as String),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => role = value!),
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                value: filter,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: '类型 / 状态',
                  contentPadding: EdgeInsets.all(10),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部')),
                  DropdownMenuItem(value: 'tool', child: Text('工具调用')),
                  DropdownMenuItem(value: 'model', child: Text('模型请求')),
                  DropdownMenuItem(value: 'failed', child: Text('失败步骤')),
                ],
                onChanged: (value) => setState(() => filter = value!),
              ),
            ),
            TextButton.icon(
              onPressed: agent.runId.isEmpty ? null : widget.onExport,
              icon: const Icon(Icons.download_outlined, size: 17),
              label: const Text('导出轨迹'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (agent.traces.isNotEmpty) _lanes(),
        const SizedBox(height: 18),
        for (final trace in traces)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE8EAF1)),
            ),
            child: ExpansionTile(
              key: ValueKey(trace['id']),
              leading: Icon(
                trace['kind'] == 'model'
                    ? Icons.auto_awesome_outlined
                    : Icons.build_outlined,
                color: color(trace['status'] as String?),
                size: 20,
              ),
              title: Text(
                '${author(trace['roleId'] as String?)} · ${trace['name']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${statusLabel(trace['status'] as String?)}${trace['durationMs'] != null ? ' · ${trace['durationMs']} ms' : ' · 等待响应'}${trace['characters'] != null ? ' · ${trace['characters']} 字符' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: color(trace['status'] as String?),
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                _detail('参数 / 输入', format(trace['input'])),
                if (trace['error'] != null)
                  _detail('错误', trace['error'] as String, isError: true),
                if (trace['output'] != null)
                  _detail('结果', format(trace['output'])),
                if (trace['status'] == 'running' &&
                    (trace['preview'] as String? ?? '').isNotEmpty)
                  _detail('正在接收的响应（尚未校验）', trace['preview'] as String),
              ],
            ),
          ),
        if (traces.isEmpty)
          const Padding(
            padding: EdgeInsets.all(22),
            child: Text('暂无符合条件的步骤。任务开始后将显示真实调用记录。'),
          ),
        const SizedBox(height: 15),
        ExpansionTile(
          title: const Text('任务事件与文件读取记录', style: TextStyle(fontSize: 12)),
          children: [
            for (final event in agent.events.where(
              (item) => ![
                'trace.started',
                'trace.finished',
                'task.state_changed',
              ].contains(item['type']),
            ))
              ListTile(
                dense: true,
                title: Text(
                  event['payload']?['summary'] as String? ??
                      event['type'] as String,
                  style: const TextStyle(fontSize: 11),
                ),
                subtitle: Text(
                  '${event['timestamp'] ?? ''}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _detail(String title, String value, {bool isError = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isError ? Colors.deepOrange : Colors.grey,
                ),
              ),
            ),
            IconButton(
              tooltip: '复制$title',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 14),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7FB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _lanes() {
    final traces = widget.agent.traces;
    final start = traces
        .map(
          (item) => DateTime.parse(
            item['startedAt'] as String,
          ).millisecondsSinceEpoch,
        )
        .reduce((a, b) => a < b ? a : b);
    final end = traces
        .map(
          (item) => item['finishedAt'] != null
              ? DateTime.parse(
                  item['finishedAt'] as String,
                ).millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch,
        )
        .reduce((a, b) => a > b ? a : b);
    final duration = (end - start).clamp(1, 1 << 40);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '执行时间线 · ${(duration / 1000).toStringAsFixed(2)} 秒',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        for (final item in widget.agent.roles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 85,
                  child: Text(
                    item['name'] as String,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Container(
                      height: 16,
                      color: const Color(0xFFEDEEF4),
                      child: Stack(
                        children: [
                          for (final trace in traces.where(
                            (trace) => trace['roleId'] == item['id'],
                          ))
                            Positioned(
                              left:
                                  ((DateTime.parse(
                                                trace['startedAt'] as String,
                                              ).millisecondsSinceEpoch -
                                              start) /
                                          duration *
                                          constraints.maxWidth)
                                      .clamp(0, constraints.maxWidth - 1),
                              width:
                                  (((trace['durationMs'] as num? ??
                                                  DateTime.now()
                                                          .millisecondsSinceEpoch -
                                                      DateTime.parse(
                                                        trace['startedAt']
                                                            as String,
                                                      ).millisecondsSinceEpoch) /
                                              duration) *
                                          constraints.maxWidth)
                                      .clamp(2, constraints.maxWidth),
                              top: 2,
                              bottom: 2,
                              child: Tooltip(
                                message:
                                    '${trace['name']} · ${statusLabel(trace['status'] as String?)}',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color(trace['status'] as String?),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
