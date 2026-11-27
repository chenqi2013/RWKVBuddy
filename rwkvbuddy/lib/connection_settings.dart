import 'package:flutter/material.dart';
import 'agent_controller.dart';
import 'windows_text_editing.dart';
import 'local_model_panel.dart';

class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key, required this.agent});
  final AgentController agent;
  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final name = TextEditingController();
  final address = TextEditingController();
  final model = TextEditingController();
  final token = TextEditingController();
  final headers = TextEditingController();
  final stateId = TextEditingController();
  final adapterId = TextEditingController();
  final concurrency = TextEditingController(text: '2');
  String? editing;
  String protocol = 'chat';
  String inferenceMode = 'online';
  String sourceFilter = 'online';
  int maxTokens = 4096;
  double temperature = 0.2;
  bool? enableThinking;
  bool? jsonOutput;
  bool testing = false;
  bool saving = false;
  Json? result;
  List<String> models = [];
  @override
  void initState() {
    super.initState();
    sourceFilter = widget.agent.usesLocalModel ? 'local' : 'online';
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      address,
      model,
      token,
      headers,
      stateId,
      adapterId,
      concurrency,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void edit(Json? profile) {
    final value = profile ?? <String, dynamic>{};
    setState(() {
      editing = value['id'] as String? ?? '';
      inferenceMode = value['inferenceMode'] as String? ?? sourceFilter;
      if (profile != null && value['inferenceMode'] == null) {
        inferenceMode = 'online';
      }
      final local = inferenceMode == 'local';
      name.text = value['name'] as String? ?? (local ? '本地 RWKV' : '');
      address.text =
          value['baseUrl'] as String? ??
          (local ? 'http://127.0.0.1:8099/v1' : '');
      model.text =
          value['model'] as String? ?? (local ? 'rwkv7-g1l-1.5b-Q4_K_M' : '');
      token.text = value['apiKey'] as String? ?? '';
      final custom = Map<String, dynamic>.from(value['headers'] as Map? ?? {});
      if ((value['accessId'] as String? ?? '').isNotEmpty) {
        custom['CF-Access-Client-Id'] = value['accessId'];
      }
      if ((value['accessSecret'] as String? ?? '').isNotEmpty) {
        custom['CF-Access-Client-Secret'] = value['accessSecret'];
      }
      headers.text = custom.entries
          .map((item) => '${item.key}: ${item.value}')
          .join('\n');
      stateId.text = value['stateId'] as String? ?? '';
      adapterId.text = value['adapterId'] as String? ?? '';
      protocol = value['protocol'] as String? ?? 'chat';
      enableThinking =
          value['enableThinking'] as bool? ?? (local ? false : null);
      jsonOutput = value['jsonOutput'] as bool?;
      concurrency.text = local ? '1' : '${value['concurrency'] ?? 2}';
      maxTokens = (value['maxTokens'] as num? ?? (local ? 1024 : 4096)).toInt();
      temperature = (value['temperature'] as num? ?? 0.2).toDouble().clamp(
        0,
        2,
      );
      result = null;
      models = [];
    });
  }

  Json draft() {
    final requestLimit = inferenceMode == 'local'
        ? 1
        : int.tryParse(concurrency.text.trim());
    if (requestLimit == null ||
        requestLimit < 1 ||
        requestLimit > 9007199254740991) {
      throw const FormatException('并发模型请求请输入有效的正整数');
    }
    final url = Uri.tryParse(address.text.trim());
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('请输入完整的 HTTP(S) 服务地址，凭据请填写到专用字段');
    }
    if (inferenceMode == 'local' &&
        !['127.0.0.1', 'localhost', '::1', '[::1]'].contains(url.host)) {
      throw const FormatException('本地模型地址必须是 localhost、127.0.0.1 或 ::1');
    }
    final custom = <String, String>{};
    for (final line
        in headers.text.split('\n').where((line) => line.trim().isNotEmpty)) {
      final colon = line.indexOf(':');
      if (colon < 1) {
        throw const FormatException('请求头格式应为 Header-Name: value，每行一个');
      }
      custom[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    return {
      if (editing?.isNotEmpty ?? false) 'id': editing,
      'name': name.text.trim().isEmpty ? url.host : name.text.trim(),
      'inferenceMode': inferenceMode,
      'baseUrl': address.text.trim(),
      'model': model.text.trim(),
      'protocol': protocol,
      'apiKey': inferenceMode == 'local' ? '' : token.text.trim(),
      'headers': inferenceMode == 'local' ? <String, String>{} : custom,
      'stateId': stateId.text.trim(),
      'adapterId': adapterId.text.trim(),
      'concurrency': requestLimit,
      'maxTokens': maxTokens,
      'temperature': temperature,
      if (protocol == 'chat' && enableThinking != null)
        'enableThinking': enableThinking,
      if (protocol == 'chat' && jsonOutput != null) 'jsonOutput': jsonOutput,
      'autoModel': model.text.trim().isEmpty,
    };
  }

  Future<void> test(bool generate) async {
    try {
      final value = draft();
      setState(() {
        testing = true;
        result = null;
      });
      final response = await widget.agent.testConnection(
        value,
        generate: generate,
      );
      if (!mounted) return;
      setState(() {
        result = response;
        testing = false;
        if (response['models'] is List) {
          models = List<String>.from(response['models'] as List);
          if (model.text.isEmpty && models.isNotEmpty) {
            model.text = models.first;
          }
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          testing = false;
          result = {'ok': false, 'summary': error.toString()};
        });
      }
    }
  }

  Future<void> save() async {
    try {
      final value = draft();
      setState(() => saving = true);
      await widget.agent.saveConnection(value);
      if (mounted) {
        setState(() {
          editing = null;
          saving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          result = {'ok': false, 'summary': error.toString()};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: Text(
        editing == null
            ? '模型服务'
            : editing!.isEmpty
            ? '新建连接'
            : '编辑连接',
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.agent,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            key: ValueKey(
              editing == null ? 'list-$sourceFilter' : 'editor-$editing',
            ),
            padding: const EdgeInsets.all(24),
            children: editing == null ? _list() : _editor(),
          ),
        ),
      ),
    ),
  );
  List<Widget> _list() => [
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'online',
          label: Text('在线 API'),
          icon: Icon(Icons.cloud_outlined),
        ),
        ButtonSegment(
          value: 'local',
          label: Text('本地模型'),
          icon: Icon(Icons.computer_outlined),
        ),
      ],
      selected: {sourceFilter},
      onSelectionChanged: (value) =>
          setState(() => sourceFilter = value.single),
    ),
    const SizedBox(height: 20),
    if (sourceFilter == 'local') LocalModelPanel(agent: widget.agent),
    Row(
      children: [
        const Expanded(
          child: Text('选择用于下一轮任务的模型服务', style: TextStyle(color: Colors.grey)),
        ),
        if (sourceFilter == 'online')
          FilledButton.icon(
            onPressed: widget.agent.busy ? null : () => edit(null),
            icon: const Icon(Icons.add),
            label: const Text('新建连接'),
          ),
      ],
    ),
    const SizedBox(height: 24),
    for (final profile in widget.agent.connections.where(
      (profile) =>
          (profile['inferenceMode'] ?? 'online') == sourceFilter &&
          profile['localModelId'] == null,
    ))
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    sourceFilter == 'local'
                        ? Icons.computer_outlined
                        : Icons.cloud_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      profile['name'] as String? ?? '远端连接',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.agent.activeConnectionId == profile['id'] &&
                      widget.agent.mode == 'rwkv')
                    const Chip(label: Text('当前连接')),
                  IconButton(
                    tooltip: '编辑连接',
                    onPressed: widget.agent.busy ? null : () => edit(profile),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${profile['model']} · ${profile['protocol'] == 'chat'
                    ? 'Chat Completions'
                    : profile['protocol'] == 'python'
                    ? 'Lightning Python'
                    : 'Lightning CUDA'}',
              ),
              const SizedBox(height: 5),
              Text(
                profile['baseUrl'] as String? ?? '',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: widget.agent.busy
                        ? null
                        : () {
                            widget.agent.activateConnection(
                              profile['id'] as String,
                            );
                            Navigator.pop(context);
                          },
                    child: const Text('使用此连接'),
                  ),
                  TextButton(
                    onPressed: widget.agent.busy
                        ? null
                        : () async {
                            final id = profile['id'] as String;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('删除连接？'),
                                content: Text(
                                  '将移除 ${profile['name']} 的配置和已保存凭据。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.agent.deleteConnection(id);
                            }
                          },
                    child: const Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    if (sourceFilter == 'online' &&
        !widget.agent.connections.any(
          (profile) => (profile['inferenceMode'] ?? 'online') == sourceFilter,
        ))
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Text('尚未添加此类模型服务，点击“新建连接”配置。'),
      ),
    const SizedBox(height: 15),
    const Divider(),
    ListTile(
      leading: const Icon(Icons.science_outlined),
      title: const Text('本地演示'),
      subtitle: const Text('离线读取资料并运行固定规则，不调用大模型'),
      trailing: OutlinedButton(
        onPressed: widget.agent.busy
            ? null
            : () {
                widget.agent.setMode('local');
                Navigator.pop(context);
              },
        child: const Text('使用演示模式'),
      ),
    ),
    const Padding(
      padding: EdgeInsets.only(top: 18),
      child: Text(
        '连接配置保存到本机，令牌和自定义请求头由系统安全存储保存。此应用不提供联网搜索。',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ),
  ];
  List<Widget> _editor() => [
    TextButton.icon(
      onPressed: testing || saving
          ? null
          : () => setState(() => editing = null),
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('连接列表'),
    ),
    const SizedBox(height: 14),
    DropdownButtonFormField<String>(
      value: inferenceMode,
      decoration: const InputDecoration(labelText: '运行模式'),
      items: [
        const DropdownMenuItem(value: 'online', child: Text('在线 API')),
        if (inferenceMode == 'local')
          const DropdownMenuItem(value: 'local', child: Text('本机 API（旧连接）')),
      ],
      onChanged: testing || saving
          ? null
          : (value) => setState(() {
              inferenceMode = value!;
              sourceFilter = value;
              if (value == 'local') {
                address.text = 'http://127.0.0.1:8099/v1';
                model.text = 'rwkv7-g1l-1.5b-Q4_K_M';
                protocol = 'chat';
                enableThinking = false;
                concurrency.text = '1';
                maxTokens = 1024;
                token.clear();
                headers.clear();
              }
              result = null;
              models = [];
            }),
    ),
    const SizedBox(height: 16),
    if (inferenceMode == 'local')
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text('请先启动本机 GGUF 服务；使用 Chat Completions，模型请求串行执行，无需 API Key。'),
      ),
    _field(name, '连接名称', hint: '例如：公司推理服务'),
    _field(address, '服务地址', hint: 'http://127.0.0.1:8000 或 https://…/v1'),
    DropdownButtonFormField<String>(
      value: protocol,
      decoration: const InputDecoration(labelText: '接口协议'),
      items: const [
        DropdownMenuItem(
          value: 'chat',
          child: Text('OpenAI 兼容 · Chat Completions'),
        ),
        DropdownMenuItem(
          value: 'rwkv',
          child: Text('RWKV Lightning CUDA · Batch'),
        ),
        DropdownMenuItem(value: 'python', child: Text('RWKV Lightning Python')),
      ],
      onChanged: testing ? null : (value) => setState(() => protocol = value!),
    ),
    const SizedBox(height: 16),
    if (protocol == 'chat' && inferenceMode != 'local')
      SwitchListTile(
        title: const Text('JSON 输出模式'),
        subtitle: const Text('RWKV 模型默认开启，约束工具调用和结果格式。服务不支持时可关闭。'),
        value: jsonOutput ?? model.text.trim().toLowerCase().startsWith('rwkv'),
        onChanged: testing || saving
            ? null
            : (value) => setState(() => jsonOutput = value),
      ),
    if (inferenceMode != 'local')
      _field(token, 'API Key / Password', secret: true, hint: '留空使用环境变量'),
    if (inferenceMode != 'local')
      ExpansionTile(
        title: const Text('自定义请求头'),
        subtitle: const Text('Cloudflare Access 或其他网关认证'),
        children: [
          WindowsTextEditing(
            controller: headers,
            enabled: !testing && !saving,
            child: TextField(
              controller: headers,
              enabled: !testing && !saving,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'CF-Access-Client-Id: …\nCF-Access-Client-Secret: …',
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: testing ? null : () => test(false),
          icon: const Icon(Icons.sync),
          label: const Text('测试连接 / 获取模型'),
        ),
        OutlinedButton.icon(
          onPressed: testing ? null : () => test(true),
          icon: const Icon(Icons.play_arrow_outlined),
          label: const Text('测试生成'),
        ),
      ],
    ),
    if (testing)
      const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      ),
    if (result != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: SelectableText(
          '${result!['summary']}${result!['latencyMs'] != null ? ' · ${result!['latencyMs']} ms' : ''}',
          style: TextStyle(
            color: result!['ok'] == true ? Colors.teal : Colors.deepOrange,
          ),
        ),
      ),
    const SizedBox(height: 16),
    _field(model, '模型名称（可选）', hint: '留空自动获取，或填写模型 ID'),
    if (models.isNotEmpty)
      DropdownButtonFormField<String>(
        value: models.contains(model.text) ? model.text : null,
        decoration: const InputDecoration(labelText: '服务返回的模型'),
        isExpanded: true,
        items: models
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => model.text = value!),
      ),
    const SizedBox(height: 12),
    ExpansionTile(
      title: const Text('生成与并发参数'),
      initiallyExpanded: false,
      children: [
        WindowsTextEditing(
          controller: concurrency,
          enabled: inferenceMode != 'local' && !testing && !saving,
          child: TextField(
            key: const Key('model-concurrency'),
            controller: concurrency,
            keyboardType: TextInputType.number,
            enabled: inferenceMode != 'local' && !testing && !saving,
            decoration: InputDecoration(
              labelText: '并发模型请求',
              helperText: inferenceMode == 'local'
                  ? '本地模型当前固定为 1'
                  : '填写正整数，例如 4、6、8；实际并发受模型服务能力影响',
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: [1024, 2048, 4096, 8192].contains(maxTokens)
              ? maxTokens
              : 4096,
          decoration: const InputDecoration(labelText: '单次最大输出 Token'),
          items: [
            1024,
            2048,
            4096,
            8192,
          ].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
          onChanged: (value) => setState(() => maxTokens = value!),
        ),
        const SizedBox(height: 12),
        Text('温度：${temperature.toStringAsFixed(1)}'),
        Slider(
          value: temperature,
          min: 0,
          max: 2,
          divisions: 20,
          onChanged: (value) => setState(() => temperature = value),
        ),
        if (protocol == 'rwkv') ...[
          _field(stateId, 'State ID（已在服务器注册，可选）'),
          _field(adapterId, 'Adapter ID（已在服务器注册，可选）'),
        ],
      ],
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: testing || saving ? null : save,
      child: Text(saving ? '正在保存…' : '保存并使用'),
    ),
    const SizedBox(height: 12),
    const Text(
      '获取模型成功仅代表列表接口可达；“测试生成”会实际请求一次模型。',
      style: TextStyle(color: Colors.grey, fontSize: 12),
    ),
  ];
  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool secret = false,
  }) => Padding(
    key: ObjectKey(controller),
    padding: const EdgeInsets.only(bottom: 16),
    child: WindowsTextEditing(
      controller: controller,
      enabled: !testing && !saving,
      child: TextField(
        controller: controller,
        onChanged: controller == model ? (_) => setState(() {}) : null,
        enabled: !testing && !saving,
        obscureText: secret,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    ),
  );
}
