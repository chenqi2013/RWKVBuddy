import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'agent_controller.dart';

/// Actual reads, model requests and tools in execution order.
class TraceView extends StatefulWidget {
  const TraceView({
    super.key,
    required this.agent,
    required this.onExport,
    this.turn,
  });
  final AgentController agent;
  final VoidCallback onExport;
  final Json? turn;

  @override
  State<TraceView> createState() => _TraceViewState();
}

class _TraceViewState extends State<TraceView> {
  AgentController get agent => widget.agent;
  Json? get turn => widget.turn;
  final expandedLists = <String>{};
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant TraceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  void _syncClock() {
    final current = turn == null || turn!['id'] == agent.runId;
    final records = current ? agent.traces : turn!['traces'] as List? ?? [];
    final running =
        (turn ?? agent.run)?['status'] == 'running' &&
        records.any(
          (trace) => trace['kind'] == 'model' && trace['status'] == 'running',
        );
    if (running) {
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Json parsed(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final result = jsonDecode(value);
        if (result is Map) return Map<String, dynamic>.from(result);
      } catch (_) {}
    }
    return {};
  }

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
    'input.read' =>
      trace['input']?['reuse'] == true
          ? '读取上一轮资料和成果'
          : parsed(trace['output'])['project'] == true
          ? '建立项目目录索引'
          : trace['input']?['sourceMode'] == 'text'
          ? '整理提问上下文'
          : '读取资料',
    'read_file' => '读取文件内容',
    'workspace.resolve' => '定位项目目录',
    'list_directory' => '浏览目录',
    'find_files' => '查找文件',
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
    // Older history has the actual input file list but no per-file events.
    if (reads.isEmpty) {
      for (final trace in traces.where(
        (trace) =>
            trace['name'] == 'input.read' &&
            trace['input']?['sourceMode'] != 'text',
      )) {
        final output = parsed(trace['output']);
        for (final path in output['files'] as List? ?? []) {
          reads.add({
            'name': '$path',
            'status': 'completed',
            'source': 'directory',
            'reused': trace['input']?['reuse'] == true,
          });
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
                onPressed: widget.onExport,
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
          _readList(reads),
        for (final trace in traces) ...[
          if (!(trace['kind'] == 'model' &&
              trace['input']?['project'] is Map &&
              trace['status'] == 'completed' &&
              (trace['progress'] as String? ?? '').isEmpty))
            _step(trace),
          if (trace['name'] == 'input.read') _readList(reads),
        ],
        if (runStatus == 'completed' &&
            traces.any((trace) => trace['kind'] == 'model') &&
            !traces.any((trace) => trace['kind'] == 'tool'))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '本轮直接基于已提供的文件片段生成结果，没有额外工具调用。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _readList(List<Json> reads) {
    if (reads.isEmpty) return const SizedBox.shrink();
    final expanded = expandedLists.contains('reads');
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件读取记录 · ${reads.length} 个',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final read in expanded ? reads : reads.take(6)) _read(read),
          if (reads.length > 6)
            TextButton(
              onPressed: () => setState(
                () => expanded
                    ? expandedLists.remove('reads')
                    : expandedLists.add('reads'),
              ),
              child: Text(expanded ? '收起文件列表' : '查看全部 ${reads.length} 个文件'),
            ),
        ],
      ),
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
                ? read['reused'] == true
                      ? '已载入保存的快照'
                      : read['source'] == 'directory'
                      ? '已读入快照${read['lines'] != null ? ' · ${read['lines']} 行' : ''}'
                      : '已读取 ${read['lines']} 行'
                : read['status'] == 'failed'
                ? '读取失败：${read['error']}'
                : read['status'] == 'cancelled'
                ? '已取消'
                : '正在读取'}',
            style: TextStyle(
              fontSize: 11,
              color: read['status'] == 'failed'
                  ? Colors.deepOrange
                  : const Color(0xFF8A8A8A),
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
              : const Color(0xFF708876),
        );

  String target(Json trace, Json input, Json output) =>
      output['path'] as String? ??
      input['path'] as String? ??
      trace['context']?['path'] as String? ??
      input['evidenceId'] as String? ??
      '';

  Widget _note(String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SelectableText(
      value,
      style: const TextStyle(
        fontSize: 11,
        height: 1.6,
        color: Color(0xFF737373),
      ),
    ),
  );

  bool _isMarkdown(String path) =>
      RegExp(r'\.(md|markdown|mdown)$', caseSensitive: false).hasMatch(path);

  Widget _markdown(String content, {double fontSize = 12}) => MarkdownBody(
    data: content,
    selectable: true,
    sizedImageBuilder: (config) =>
        Text(config.alt ?? config.title ?? config.uri.toString()),
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(fontSize: fontSize, height: 1.7),
      h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      code: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(6),
      ),
      blockSpacing: 10,
    ),
  );

  Widget _operation(Json trace) {
    final input = parsed(trace['input']);
    final output = parsed(trace['output']);
    final name = trace['name'];
    final rows = <Widget>[];
    if (trace['kind'] == 'model') {
      final project = input['project'] is Map;
      final files = (input['sourceTexts'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final toolResults = input['toolResults'] as List? ?? [];
      if (!project) {
        rows.add(_note('分析任务：${input['question'] ?? '根据本轮资料完成用户要求'}'));
      }
      if (files.isNotEmpty) {
        rows.add(
          _note(
            '提供给模型：${files.length} 个文件片段${toolResults.isNotEmpty ? ' · ${toolResults.length} 条工具结果' : ''}',
          ),
        );
        final key = '${trace['id']}-sources';
        final expanded = expandedLists.contains(key);
        for (final file in expanded ? files : files.take(4)) {
          rows.add(
            _note(
              '• ${file['path']} · ${(file['excerpt'] as String? ?? '').length} 字符片段',
            ),
          );
        }
        if (files.length > 4) {
          rows.add(
            TextButton(
              onPressed: () => setState(
                () => expanded
                    ? expandedLists.remove(key)
                    : expandedLists.add(key),
              ),
              child: Text(
                expanded ? '收起分析资料' : '查看提供给模型的全部 ${files.length} 个片段',
              ),
            ),
          );
        }
      }
      if (trace['status'] == 'running') {
        final started = DateTime.tryParse('${trace['startedAt']}');
        final elapsed = started == null
            ? 0
            : DateTime.now().difference(started).inSeconds.clamp(0, 86400);
        final hasContent = (trace['characters'] as num? ?? 0) > 0;
        final stage = switch (trace['phase']) {
          'queued' => '等待模型请求资源',
          'requesting' => '请求已发出，等待服务端响应',
          _ => '正在等待模型响应',
        };
        rows.add(
          _note(
            hasContent
                ? '正在接收模型响应 · ${trace['characters']} 字符'
                : '$stage · 已等待 $elapsed 秒',
          ),
        );
        if (!hasContent && elapsed >= 15) {
          rows.add(_note('服务端尚未返回可展示的内容，收到后会在这里实时更新。'));
        }
      } else if (trace['status'] == 'completed' && !project) {
        if (output['tool'] != null) {
          final args = parsed(output['arguments']);
          rows.add(
            _note(
              '模型选择下一步：${output['tool']} ${args['evidenceId'] ?? args['query'] ?? args['expression'] ?? ''}',
            ),
          );
        } else if (output['answer'] != null) {
          rows.add(
            _note(
              '已生成回答${output['files'] is List ? '，提交 ${(output['files'] as List).length} 个成果文件' : ''}',
            ),
          );
        }
      }
      final progress =
          trace['progress'] as String? ?? output['progress'] as String? ?? '';
      if (progress.isNotEmpty) {
        rows.add(
          project
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _markdown(progress, fontSize: 13),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _markdown('模型进度说明：$progress'),
                ),
        );
      }
      final draft = trace['answerPreview'] as String? ?? '';
      if (draft.isNotEmpty && trace['status'] != 'completed') {
        rows.add(
          _note(
            trace['status'] == 'running'
                ? '回答草稿 · 正在生成，尚未完成'
                : '回答草稿 · 已中断，未作为结果提交',
          ),
        );
        rows.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(child: _markdown(draft)),
            ),
          ),
        );
      }
      final pendingTool = trace['pendingTool'] as String? ?? '';
      if (pendingTool.isNotEmpty && trace['status'] == 'running') {
        rows.add(_note('正在生成工具请求：$pendingTool（尚未执行）'));
      }
    } else if (name == 'workspace.resolve') {
      rows.add(_note('请求路径：${input['path']}'));
      if (output['root'] != null) {
        rows.add(
          _note(
            '项目目录：${output['root']}${output['corrected'] == true ? '（已校正路径）' : ''}',
          ),
        );
      }
    } else if (name == 'list_directory' || name == 'find_files') {
      rows.add(
        _note(
          '${input['path'] ?? '.'}${name == 'find_files' ? ' · ${input['pattern'] ?? '*'}' : ''}',
        ),
      );
      final entries = output['entries'] as List? ?? [];
      if (trace['status'] == 'completed') {
        rows.add(
          _note(
            '返回 ${entries.length} 项 · 共 ${output['total'] ?? entries.length} 项${output['hasMore'] == true ? ' · 后续内容可继续分页' : ''}',
          ),
        );
        final key = 'entries-${trace['id']}';
        final expanded = expandedLists.contains(key);
        rows.add(
          _preview(
            (expanded ? entries : entries.take(8))
                .map(
                  (entry) =>
                      '${entry['type'] == 'directory' ? '▸ ' : '  '}${entry['path']}${entry['type'] == 'directory' ? '/' : ''}',
                )
                .join('\n'),
            maxLines: expanded ? 20 : 8,
          ),
        );
        if (entries.length > 8) {
          rows.add(
            TextButton(
              onPressed: () => setState(
                () => expanded
                    ? expandedLists.remove(key)
                    : expandedLists.add(key),
              ),
              child: Text(expanded ? '收起目录列表' : '展开本次 ${entries.length} 项'),
            ),
          );
        }
      }
    } else if (name == 'input.read') {
      if ((input['workspace'] as String? ?? '').isNotEmpty) {
        rows.add(_note('目录：${input['workspace']}'));
      }
      if (output['project'] == true) {
        rows.add(_note('已索引 ${output['entryCount']} 个目录项 · 正文按需读取'));
      } else if (output['fileCount'] != null) {
        rows.add(_note('已将 ${output['fileCount']} 个文件读入本地快照；模型分析范围见下方记录。'));
      }
      if (input['reuse'] == true) {
        rows.add(
          _note(
            output['project'] == true
                ? '复用目录索引和已读取内容；尚未缓存的文件需要访问原目录。'
                : '复用已保存的资料和成果快照，未重新读取原文件。',
          ),
        );
      }
      for (final warning in output['warnings'] as List? ?? []) {
        rows.add(_note('$warning'));
      }
    } else if (name == 'read_file') {
      final path = target(trace, input, output);
      rows.add(
        _note(
          '读取：$path · 第 ${output['startLine'] ?? input['startLine'] ?? 1}–${output['endLine'] ?? ((input['startLine'] as num? ?? 1) + (input['lineCount'] as num? ?? 60) - 1)} 行',
        ),
      );
      if (output['text'] is String) {
        rows.add(_filePreview(trace, path, output['text'] as String));
        if (output['hasMore'] == true) {
          rows.add(
            _note(
              '文件共 ${output['totalLines']} 行 · 可从第 ${output['nextStartLine']} 行继续读取',
            ),
          );
        }
      }
    } else if (name == 'search_text') {
      rows.add(
        _note(
          '检索：${input['query'] ?? ''}${input['path'] != null ? ' · ${input['path']}' : ''}',
        ),
      );
      if (output['scannedFiles'] != null) {
        rows.add(
          _note(
            '本次搜索 ${output['scannedFiles']} 个文件${output['hasMore'] == true ? ' · 仍有文件未搜索' : ''}',
          ),
        );
      }
      if (output['matches'] is List) {
        final matches = output['matches'] as List;
        rows.add(
          _note(
            '找到 ${matches.length} 处匹配${output['limited'] == true ? '（已达显示上限）' : ''}',
          ),
        );
        for (final match in matches.take(3)) {
          rows.add(
            _note('${match['path']}:${match['line']} · ${match['text']}'),
          );
        }
      }
      for (final error in output['errors'] as List? ?? []) {
        rows.add(_note('${error['path']}：${error['error']}'));
      }
    } else if (name == 'calculator') {
      rows.add(
        _note(
          '${input['expression'] ?? ''}${output['result'] != null ? ' = ${output['result']}' : ''}',
        ),
      );
    } else if (name == 'files.create') {
      final files = output['files'] as List? ?? input['files'] as List? ?? [];
      for (final file in files) {
        rows.add(
          _note(
            '${trace['status'] == 'completed' ? '已生成' : '生成'}：${file['name']}',
          ),
        );
      }
    } else if (name == 'local.analyze') {
      rows.add(_note('本地规则整理 ${input['fileCount'] ?? ''} 份资料，未调用远端模型。'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _preview(String content, {int maxLines = 5}) {
    final preview = content.length > 2000
        ? '${content.substring(0, 2000)}…'
        : content;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        preview,
        minLines: 1,
        maxLines: maxLines,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _filePreview(Json trace, String path, String content) {
    final markdown = _isMarkdown(path);
    final rawKey = 'source-${trace['id']}';
    final raw = expandedLists.contains(rawKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (markdown)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Markdown 预览',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              TextButton(
                key: ValueKey(rawKey),
                onPressed: () => setState(
                  () => raw
                      ? expandedLists.remove(rawKey)
                      : expandedLists.add(rawKey),
                ),
                child: Text(raw ? '查看排版' : '查看原文'),
              ),
            ],
          ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: markdown && !raw
                  ? _markdown(content)
                  : SelectableText(
                      content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _outputDetail(Json trace) {
    final output = parsed(trace['output']);
    if (trace['name'] != 'read_file' || output['text'] is! String) {
      return _detail('输出', format(trace['output']));
    }
    final rawKey = 'raw-output-${trace['id']}';
    final raw = expandedLists.contains(rawKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detail(
          '文件正文',
          output['text'] as String,
          markdown: _isMarkdown(
            '${output['path'] ?? trace['context']?['path'] ?? trace['input']?['path'] ?? ''}',
          ),
        ),
        TextButton(
          key: ValueKey(rawKey),
          onPressed: () => setState(
            () =>
                raw ? expandedLists.remove(rawKey) : expandedLists.add(rawKey),
          ),
          child: Text(raw ? '收起原始 JSON' : '查看原始 JSON'),
        ),
        if (raw) _detail('原始输出', format(trace['output'])),
      ],
    );
  }

  Widget _step(Json trace) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      border: Border.all(
        color: trace['kind'] == 'model' && trace['input']?['project'] is Map
            ? Colors.transparent
            : trace['status'] == 'running'
            ? const Color(0xFFCFD9D0)
            : const Color(0xFFEAEAEA),
      ),
      borderRadius: BorderRadius.circular(12),
      color: trace['status'] == 'running'
          ? const Color(0xFFFCFDFC)
          : Colors.white,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _indicator(trace['status'] as String?),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trace['kind'] == 'model' &&
                                    trace['input']?['project'] is Map
                                ? '处理说明'
                                : title(trace),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: ValueKey('details-${trace['id']}'),
                          onPressed: () => setState(
                            () =>
                                expandedLists.contains('details-${trace['id']}')
                                ? expandedLists.remove('details-${trace['id']}')
                                : expandedLists.add('details-${trace['id']}'),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                          ),
                          icon: Icon(
                            expandedLists.contains('details-${trace['id']}')
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 14,
                          ),
                          label: const Text(
                            '调用详情',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      [
                        if (trace['kind'] == 'model' || trace['kind'] == 'tool')
                          '${trace['name']}',
                        statusLabel(trace['status'] as String?),
                        if (trace['durationMs'] != null)
                          '${(trace['durationMs'] / 1000).toStringAsFixed(1)} 秒',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    _operation(trace),
                    if (trace['error'] != null)
                      Text(
                        '${trace['error']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.deepOrange,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (expandedLists.contains('details-${trace['id']}'))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                if (trace['input'] != null)
                  _detail('输入', format(trace['input'])),
                if (trace['error'] != null) _detail('错误', '${trace['error']}'),
                if (trace['output'] != null) _outputDetail(trace),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _detail(String label, String value, {bool markdown = false}) => Column(
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
        color: const Color(0xFFF7F7F7),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: markdown
                ? _markdown(value)
                : SelectableText(
                    value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
          ),
        ),
      ),
    ],
  );
}
