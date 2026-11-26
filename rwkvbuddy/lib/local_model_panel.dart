import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'agent_controller.dart';

class LocalModelPanel extends StatefulWidget {
  const LocalModelPanel({super.key, required this.agent});
  final AgentController agent;
  @override
  State<LocalModelPanel> createState() => _LocalModelPanelState();
}

class _LocalModelPanelState extends State<LocalModelPanel> {
  String error = '';
  bool picking = false;

  Future<void> perform(Future<void> Function() action) async {
    setState(() => error = '');
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> import() async {
    setState(() => picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'GGUF 模型', extensions: ['gguf']),
        ],
      );
      if (file != null && mounted) {
        await perform(() => widget.agent.importLocalModel(file.path));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final state = agent.localModelState;
    final loading = state['status'] == 'loading';
    final locked = agent.busy || agent.localModelOperation || picking;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '导入本地模型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '选择电脑上的 GGUF 文件，应用会直接在本机加载并推理，无需启动 HTTP 服务。文件保留在原位置，请勿移动或删除。',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('import-gguf'),
              onPressed: locked || !agent.connected ? null : import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('导入 GGUF 并加载'),
            ),
            const SizedBox(height: 12),
            if (!agent.connected) const Text('正在连接本地执行服务…'),
            if (agent.connected && !agent.localRuntimeAvailable)
              const Text(
                '当前安装包缺少推理组件，请使用包含本地模型运行时的完整发布包。',
                style: TextStyle(color: Colors.deepOrange),
              ),
            Text(state['message'] as String? ?? '尚未加载模型'),
            if (loading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value:
                    state['progress'] is num && (state['progress'] as num) < 100
                    ? (state['progress'] as num).toDouble() / 100
                    : null,
              ),
            ],
            if (loading || state['status'] == 'ready')
              TextButton.icon(
                onPressed: agent.busy || (agent.localModelOperation && !loading)
                    ? null
                    : () => perform(agent.stopLocalModel),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(loading ? '取消加载' : '卸载模型 / 释放内存'),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(
                  error,
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              ),
            if (state['status'] == 'failed' &&
                (state['detail'] as String? ?? '').isNotEmpty)
              ExpansionTile(
                title: const Text('加载错误详情'),
                children: [
                  SelectableText(
                    state['detail'] as String,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            for (final model in agent.localModels) ...[
              const Divider(height: 28),
              Text(
                model['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${((model['bytes'] as num) / 1024 / 1024).toStringAsFixed(0)} MiB · ${model['path']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: locked || !agent.connected
                        ? null
                        : () => perform(
                            () => agent.loadLocalModel(model['id'] as String),
                          ),
                    child: Text(
                      state['modelId'] == model['id'] &&
                              state['status'] == 'ready'
                          ? '使用已加载模型'
                          : '加载并使用',
                    ),
                  ),
                  if (state['modelId'] == model['id'] &&
                      state['status'] == 'ready' &&
                      agent.config['localModelId'] == model['id'])
                    FilledButton(
                      onPressed: agent.busy
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('开始对话'),
                    ),
                  TextButton(
                    onPressed: locked || !agent.connected
                        ? null
                        : () => perform(
                            () => agent.removeLocalModel(model['id'] as String),
                          ),
                    child: const Text('移除记录'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '移除记录不会删除原始模型。模型须与推理组件兼容，损坏或不支持的文件会显示加载错误。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
