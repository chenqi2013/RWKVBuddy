import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'agent_controller.dart';

/// Actual reads, model requests and tools in execution order.
class TraceView extends StatelessWidget {
  const TraceView({
    super.key,
    required this.agent,
    required this.onExport,
    this.turn,
  });
  final AgentController agent;
  final VoidCallback onExport;
  final Json? turn;

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

  String title(Json trace) => switch (trace['name']) {
    'input.read' => trace['input']?['reuse'] == true ? '读取上一轮资料和成果' : '读取资料',
    'read_file' => '读取文件内容',
    'search_text' => '检索文件内容',
    'calculator' => '计算数据',
    'files.create' => '生成成果文件',
    'lua.ledger' => '核算经营数据',
    'lua.cash' => '核算资金流水',
    'local.analyze' => '整理资料与本地分析',
    _ => trace['kind'] == 'model' ? '分析与整理' : '调用工具：${trace['name']}',
  };

  @override
  Widget build(BuildContext context) {
    final current = turn == null || turn!['id'] == agent.runId;
    final traces =
        (current ? agent.traces : (turn!['traces'] as List? ?? []).cast<Json>())
            .where((trace) => trace['name'] != 'snapshot.inspect')
            .map(
              (trace) =>
                  trace['status'] == 'running' &&
                      (turn ?? agent.run)?['status'] == 'interrupted'
                  ? {...trace, 'status': 'interrupted'}
                  : trace,
            )
            .toList();
    final events = current
        ? agent.events
        : (turn!['events'] as List? ?? []).cast<Json>();
    // Pair a read with its actual completion, preserving duplicate filenames.
    final reads = <Json>[];
    for (final event in events) {
      final type = event['type'];
      if (type == 'input.file_started') {
        reads.add({
          ...Map<String, dynamic>.from(event['payload'] as Map),
          'status': 'running',
        });
      } else if (type == 'input.file_parsed' || type == 'input.file_rejected') {
        final payload = Map<String, dynamic>.from(event['payload'] as Map);
        final index = reads.indexWhere(
          (r) => r['name'] == payload['name'] && r['status'] == 'running',
        );
        final read = {
          ...payload,
          'status': type == 'input.file_parsed' ? 'completed' : 'failed',
        };
        if (index < 0) {
          reads.add(read);
        } else {
          reads[index] = read;
        }
      }
    }
    final runStatus = (turn ?? agent.run)?['status'];
    if (runStatus != null && runStatus != 'running') {
      for (final read in reads.where((read) => read['status'] == 'running')) {
        read['status'] = runStatus == 'failed' ? 'failed' : 'cancelled';
        read['error'] = '读取已中断';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '处理过程',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (current && agent.runId.isNotEmpty)
              IconButton(
                tooltip: '导出处理记录',
                visualDensity: VisualDensity.compact,
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined, size: 16),
              ),
          ],
        ),
        if (traces.isEmpty && reads.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              (turn ?? agent.run)?['status'] == 'running'
                  ? '正在准备资料…'
                  : '暂无处理记录',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (!traces.any((trace) => trace['name'] == 'input.read'))
          for (final read in reads) _read(read),
        for (final trace in traces) ...[
          _step(trace),
          if (trace['name'] == 'input.read')
            for (final read in reads) _read(read),
        ],
      ],
    );
  }

  Widget _read(Json read) => Padding(
    padding: const EdgeInsets.only(left: 20, bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _indicator(read['status'] as String?),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${read['name']} · ${read['status'] == 'completed'
                ? '已读取 ${read['lines']} 行'
                : read['status'] == 'failed'
                ? '读取失败：${read['error']}'
                : read['status'] == 'cancelled'
                ? '已取消'
                : '正在读取'}',
            style: TextStyle(
              fontSize: 11,
              color: read['status'] == 'failed'
                  ? Colors.deepOrange
                  : const Color(0xFF767D90),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _indicator(String? status) => status == 'running'
      ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        )
      : Icon(
          status == 'failed'
              ? Icons.error_outline
              : (status == 'cancelled' || status == 'interrupted')
              ? Icons.stop_circle_outlined
              : Icons.check_circle_outline,
          size: 14,
          color: status == 'failed'
              ? Colors.deepOrange
              : (status == 'cancelled' || status == 'interrupted')
              ? Colors.grey
              : Colors.teal,
        );

  Widget _step(Json trace) => ExpansionTile(
    key: ValueKey(trace['id']),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(left: 22, bottom: 12),
    dense: true,
    shape: const Border(),
    collapsedShape: const Border(),
    leading: _indicator(trace['status'] as String?),
    title: Text(title(trace), style: const TextStyle(fontSize: 12)),
    subtitle: Text(
      [
        if (trace['kind'] == 'model' || trace['kind'] == 'tool')
          '${trace['name']}',
        statusLabel(trace['status'] as String?),
        if (trace['durationMs'] != null)
          '${(trace['durationMs'] / 1000).toStringAsFixed(1)} 秒',
        if (trace['error'] != null) '${trace['error']}',
      ].join(' · '),
      style: TextStyle(
        fontSize: 10,
        color: trace['status'] == 'failed' ? Colors.deepOrange : Colors.grey,
      ),
    ),
    children: [
      if (trace['input'] != null) _detail('输入', format(trace['input'])),
      if (trace['error'] != null) _detail('错误', '${trace['error']}'),
      if (trace['output'] != null) _detail('输出', format(trace['output'])),
      if (trace['status'] == 'running' && trace['characters'] != null)
        Text(
          '正在接收响应 · ${trace['characters']} 字符',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
    ],
  );

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          IconButton(
            tooltip: '复制$label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 14),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        color: const Color(0xFFF6F7FB),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, height: 1.6),
            ),
          ),
        ),
      ),
    ],
  );
}
