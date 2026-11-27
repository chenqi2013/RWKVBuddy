import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef Json = Map<String, dynamic>;

// The login Keychain supports local macOS builds without a provisioning profile.
const connectionStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);

String statusLabel(String? status) =>
    const {
      'running': '进行中',
      'waiting_dependency': '等待交接',
      'waiting_model': '等待模型',
      'waiting_tool': '等待工具',
      'submitted': '已提交',
      'verified': '已复核',
      'failed': '失败',
      'cancelled': '已取消',
      'blocked': '无法继续',
      'completed': '已完成',
      'partial': '部分完成',
      'interrupted': '已中断',
      'queued': '待开始',
    }[status] ??
    '待开始';

class AgentController extends ChangeNotifier {
  AgentController({bool autoConnect = true, this.serviceEnvironment}) {
    if (autoConnect) unawaited(connect());
  }
  final Map<String, String>? serviceEnvironment;
  Process? _process;
  bool _disposed = false;
  bool _connecting = false;
  Future<void> _preferencesWrite = Future<void>.value();
  String _preferencesError = '';
  int _defaultConnectionVersion = 0;
  bool connected = false;
  final _secureStorage = connectionStorage;
  final Map<String, Completer<Json>> _requests = {};
  List<Json> connections = [];
  String activeConnectionId = '';
  bool inputsChanged = false;
  bool busy = false;
  bool groupChat = false;
  List<Json> expertLibrary = [];
  Json team = {
    'name': '创作与研发团队',
    'members': [
      {'id': 'strategy', 'name': '策划', 'prompt': '分析目标、用户和约束，提出方案方向与执行步骤。'},
      {
        'id': 'copywriter',
        'name': '文案',
        'prompt': '根据用户目标和已有讨论，撰写清晰、具体、可使用的内容。',
      },
      {'id': 'designer', 'name': '设计', 'prompt': '提出视觉、交互和信息呈现建议，说明设计依据与交付要求。'},
      {
        'id': 'developer',
        'name': '研发',
        'prompt': '评估技术可行性、实现步骤和风险，明确已核实与待验证的部分。',
      },
    ],
  };

  void configureTeam(bool enabled, Json value) {
    if (busy) return;
    groupChat = enabled;
    team = value;
    final saved = {for (final member in expertLibrary) member['id']: member};
    for (final member in _maps(value['members'])) {
      saved[member['id']] = member;
    }
    expertLibrary = saved.values.toList();
    update();
    unawaited(savePreferences());
  }

  String error = '';
  String notice = '';
  String workspace = '';
  String sampleWorkspace = '';
  String sourceMode = 'directory';
  List<String> selectedFiles = [];
  String dataRoot = '';
  String mode = 'local';
  Json? run;
  List<Json> history = [];
  List<Json> events = [];
  List<Json> traces = [];
  List<Json> turns = [];
  Json config = {
    'baseUrl': '',
    'model': '',
    'protocol': 'chat',
    'concurrency': 2,
  };
  List<Json> localModels = [];
  Json localModelState = {'status': 'idle', 'message': '尚未加载模型'};
  bool localRuntimeAvailable = false;
  bool localModelOperation = false;
  String get report => run?['report'] as String? ?? '';
  String get answer => run?['answer'] as String? ?? '';
  bool get usesLocalModel =>
      mode == 'rwkv' && config['inferenceMode'] == 'local';
  String get connectionLabel => mode == 'local'
      ? '本地演示'
      : '${usesLocalModel ? '本地模型' : '在线 API'} · ${config['name'] as String? ?? '模型服务'}';
  String get reportPath => run?['reportPath'] as String? ?? '';
  String get runId => run?['id'] as String? ?? '';
  Json? get generationSpeed {
    final models = traces.where((trace) => trace['kind'] == 'model');
    if (models.isEmpty) return null;
    final generation = models.last['generation'];
    return generation is Map ? Map<String, dynamic>.from(generation) : null;
  }

  void update() {
    if (!_disposed) notifyListeners();
  }

  Future<String> _findService() async {
    final overridden = Platform.environment['RWKVBUDDY_SERVICE_DIR'];
    final exe = File(Platform.resolvedExecutable).parent.path;
    for (final path in [
      ?overridden,
      '$exe${Platform.pathSeparator}agent-service',
      if (Platform.isMacOS) '$exe/../Resources/agent-service',
      '${Directory.current.path}${Platform.pathSeparator}agent-service',
    ]) {
      if (await File('$path${Platform.pathSeparator}service.mjs').exists()) {
        return path;
      }
    }
    throw const FileSystemException('找不到本地执行服务，请从项目目录运行，或使用完整发布目录');
  }

  Future<void> connect() async {
    if (_connecting || connected || _disposed) return;
    _connecting = true;
    error = '';
    update();
    try {
      final root = await _findService();
      final bundled =
          '$root${Platform.pathSeparator}runtime${Platform.pathSeparator}${Platform.isWindows ? 'node.exe' : 'node'}';
      final node = await File(bundled).exists() ? bundled : 'node';
      final process = await Process.start(
        node,
        ['$root${Platform.pathSeparator}service.mjs'],
        workingDirectory: root,
        environment: serviceEnvironment,
      );
      if (_disposed) {
        process.kill();
        return;
      }
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                _event(Map<String, dynamic>.from(jsonDecode(line) as Map));
              } catch (_) {
                error = '本地服务返回了无法识别的数据';
                update();
              }
            },
            onError: (_) {
              error = '本地服务连接中断';
              update();
            },
          );
      process.stderr.transform(utf8.decoder).listen((_) {});
      unawaited(
        process.exitCode.then((code) {
          if (_disposed || _process != process) return;
          connected = false;
          busy = false;
          _process = null;
          error = '本地执行服务已退出（$code），可点击重新连接。';
          localModelState = {'status': 'idle', 'message': '本地执行服务已退出'};
          for (final request in _requests.values) {
            if (!request.isCompleted) {
              request.complete({'ok': false, 'summary': error});
            }
          }
          _requests.clear();
          update();
        }),
      );
    } catch (exception) {
      error = '无法启动本地服务：$exception';
    } finally {
      _connecting = false;
      update();
    }
  }

  void _event(Json event) {
    final payload = Map<String, dynamic>.from(event['payload'] as Map? ?? {});
    switch (event['type']) {
      case 'local.models':
        _localModels(payload);
      case 'local.result':
        _requests.remove(payload['requestId'])?.complete(payload);
      case 'connection.result':
        final id = payload['requestId'] as String?;
        _requests.remove(id)?.complete(payload);
      case 'service.ready':
        if (payload['localModels'] is Map) {
          _localModels(
            Map<String, dynamic>.from(payload['localModels'] as Map),
          );
        }
        sampleWorkspace = payload['sampleWorkspace'] as String;
        dataRoot = payload['dataRoot'] as String;
        config['baseUrl'] = payload['baseUrl'];
        config['model'] = payload['model'];
        history = _maps(payload['runs']);
        unawaited(
          _loadPreferences().then((_) async {
            if (payload['defaultConnection'] is Map) {
              await installDefaultConnection(
                Map<String, dynamic>.from(payload['defaultConnection'] as Map),
              );
            }
            connected = true;
            update();
          }),
        );
      case 'history':
        history = _maps(payload['runs']);
      case 'run.deleted':
        final deletedId = payload['runId'] as String;
        history.removeWhere((item) => item['id'] == deletedId);
        if (runId == deletedId) {
          newTask();
        } else {
          turns.removeWhere((item) => item['id'] == deletedId);
        }
      case 'run.started':
        run = Map<String, dynamic>.from(payload['run'] as Map);
        events = [];
        traces = [];
        busy = true;
        error = '';
      case 'run.loaded':
        final loaded = Map<String, dynamic>.from(payload['run'] as Map);
        run = loaded;
        groupChat = loaded['team'] is Map;
        if (groupChat) team = Map<String, dynamic>.from(loaded['team'] as Map);
        events = _maps(loaded['events']);
        traces = _maps(loaded['traces']);
        turns = _maps(payload['turns']);
        inputsChanged = false;
        workspace = loaded['workspace'] as String;
        sourceMode = loaded['sourceMode'] as String? ?? 'directory';
        selectedFiles = List<String>.from(
          loaded['selectedFiles'] as List? ?? [],
        );
        error = loaded['error'] as String? ?? '';
      case 'trace.started':
      case 'trace.finished':
        final trace = Map<String, dynamic>.from(payload['trace'] as Map);
        final index = traces.indexWhere((item) => item['id'] == trace['id']);
        if (index < 0) {
          traces.add(trace);
        } else {
          traces[index] = trace;
        }
      case 'trace.delta':
        final index = traces.indexWhere((item) => item['id'] == payload['id']);
        if (index >= 0) traces[index].addAll(payload);
      case 'team.updated':
        run?['team'] = payload['team'];
        run?['template'] = payload['template'];
      case 'team.assigned':
        run?['tasks'] = {
          for (final task in _maps(payload['tasks'])) task['roleId']: task,
        };
        run?['assignmentSummary'] = payload['summary'];
      case 'message.updated':
        final message = Map<String, dynamic>.from(payload['message'] as Map);
        final messages = _maps(run?['messages']);
        final index = messages.indexWhere(
          (item) => item['id'] == message['id'],
        );
        if (index < 0) {
          messages.add(message);
        } else {
          messages[index] = message;
        }
        run?['messages'] = messages;
      case 'plan.created':
        run?['template'] = payload['template'];
      case 'input.completed':
        run?['attachments'] = payload['attachments'];
      case 'input.resolved':
        workspace = payload['workspace'] as String;
        sourceMode = 'directory';
        selectedFiles = [];
        run?.addAll(payload);
      case 'files.created':
        run?['deliverables'] = payload['files'];
      case 'run.error':
        error = payload['message'] as String;
      case 'run.finished':
        run?.addAll(payload);
        if (payload['workspace'] is String) {
          workspace = payload['workspace'] as String;
          sourceMode = payload['sourceMode'] as String? ?? sourceMode;
        }
        busy = false;
        error = payload['error'] as String? ?? '';
      case 'report.exported':
        notice = '报告已保存到 ${payload['path']}';
      case 'file.exported':
        notice = '成果文件已保存到 ${payload['path']}';
      case 'trace.exported':
        notice = '执行轨迹已保存到 ${payload['path']}';
      case 'service.error':
        error = payload['message'] as String;
        if (run == null || run!['status'] != 'running') busy = false;
    }
    if (event['runId'] == runId &&
        event['type'] != 'run.started' &&
        event['type'] != 'trace.delta') {
      events.add(event);
      if (events.length > 1200) events.removeAt(0);
    }
    update();
  }

  static List<Json> _maps(dynamic value) => (value as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  void send(Json command) {
    if (!connected || _process == null) {
      error = '本地服务尚未连接';
      busy = false;
      update();
      return;
    }
    _process!.stdin.writeln(jsonEncode(command));
  }

  void start(String question) {
    if (busy || question.trim().isEmpty) return;
    if (config['localModelId'] != null &&
        mode == 'rwkv' &&
        (localModelState['status'] != 'ready' ||
            localModelState['modelId'] != config['localModelId'])) {
      error = '请在“模型服务 → 本地模型”中加载此模型后再使用';
      update();
      return;
    }
    if (groupChat && mode != 'rwkv') {
      error = '专家团群聊需要模型，请先在“模型服务”中启用在线 API 或本地模型';
      update();
      return;
    }
    if (sourceMode == 'files' && selectedFiles.isEmpty) {
      error = '请先添加文件或选择资料目录';
      update();
      return;
    }
    error = '';
    notice = '';
    busy = true;
    final parentRunId = runId;
    if (run != null) {
      turns.add({
        ...run!,
        'traces': List<Json>.from(traces),
        'events': List<Json>.from(events),
      });
    }
    final reuse = parentRunId.isNotEmpty && !inputsChanged;
    final actualSource = sourceMode == 'files'
        ? 'files'
        : workspace.isEmpty
        ? 'text'
        : 'directory';
    run = null;
    events = [];
    traces = [];
    send({
      'type': 'run',
      'question': question.trim(),
      'workspace': workspace,
      'sourceMode': actualSource,
      if (parentRunId.isNotEmpty) 'parentRunId': parentRunId,
      'reuseInputs': reuse,
      'selectedFiles': List<String>.from(selectedFiles),
      'mode': mode,
      'outputMode': 'auto',
      if (groupChat) 'team': team,
      'config': config,
    });
    inputsChanged = false;
    update();
  }

  void cancel() => send({'type': 'cancel', 'runId': runId});
  void pinRun(String id, bool pinned) =>
      send({'type': 'run.pin', 'runId': id, 'pinned': pinned});
  void deleteRun(String id) => send({'type': 'run.delete', 'runId': id});
  void load(String id) {
    if (!busy) send({'type': 'load', 'runId': id});
  }

  void newTask() {
    if (busy) return;
    groupChat = false;
    run = null;
    events = [];
    traces = [];
    turns = [];
    error = '';
    notice = '';
    sourceMode = 'directory';
    workspace = '';
    selectedFiles = [];
    inputsChanged = false;
    update();
  }

  void useSample() {
    if (!busy) {
      workspace = sampleWorkspace;
      sourceMode = 'directory';
      selectedFiles = [];
      inputsChanged = true;
      update();
    }
  }

  void setWorkspace(String value) {
    if (busy) return;
    workspace = value;
    sourceMode = 'directory';
    selectedFiles = [];
    inputsChanged = true;
    update();
    unawaited(savePreferences());
  }

  void addFiles(Iterable<String> paths) {
    if (busy) return;
    final next = <String>[];
    final seen = <String>{};
    for (final path in [...selectedFiles, ...paths]) {
      final key = Platform.isWindows ? path.toLowerCase() : path;
      if (seen.add(key)) next.add(path);
    }
    if (next.length > 20) {
      error = '每次最多添加 20 个文件，请移除部分文件后重试';
      update();
      return;
    }
    if (next.isEmpty) return;
    selectedFiles = next;
    inputsChanged = true;
    sourceMode = 'files';
    error = '';
    update();
  }

  void removeFile(String path) {
    if (busy) return;
    selectedFiles = selectedFiles.where((item) => item != path).toList();
    inputsChanged = true;
    update();
  }

  void setMode(String value) {
    mode = value;
    update();
    unawaited(savePreferences());
  }

  void configure(Json value) {
    config = {...config, ...value};
    update();
    unawaited(savePreferences());
  }

  Future<Json> testConnection(Json draft, {bool generate = false}) async {
    if (!connected) return {'ok': false, 'summary': '本地执行服务尚未连接'};
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<Json>();
    _requests[id] = completer;
    send({
      'type': 'connection.test',
      'requestId': id,
      'config': draft,
      'generate': generate,
    });
    try {
      return await completer.future.timeout(
        Duration(
          seconds: draft['inferenceMode'] == 'local' && generate ? 150 : 30,
        ),
      );
    } catch (_) {
      return {'ok': false, 'summary': '连接测试超时，请检查网络与地址'};
    } finally {
      _requests.remove(id);
    }
  }

  void _localModels(Json payload) {
    localModels = _maps(payload['models']);
    localModelState = Map<String, dynamic>.from(payload['state'] as Map? ?? {});
    localRuntimeAvailable = payload['runtimeAvailable'] == true;
  }

  Future<Json> _modelCommand(
    String type, {
    String? path,
    String? modelId,
  }) async {
    if (!connected) throw StateError('本地执行服务尚未连接');
    final id = 'model-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<Json>();
    _requests[id] = completer;
    send({'type': type, 'requestId': id, 'path': ?path, 'modelId': ?modelId});
    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 200),
      );
      if (response['ok'] != true) {
        throw StateError(response['summary'] as String? ?? '模型操作失败');
      }
      return response;
    } finally {
      _requests.remove(id);
    }
  }

  Future<void> importLocalModel(String path) async {
    if (busy || localModelOperation) return;
    localModelOperation = true;
    update();
    try {
      final response = await _modelCommand('local.import', path: path);
      final model = Map<String, dynamic>.from(response['model'] as Map);
      await _loadLocalModel(model['id'] as String);
    } finally {
      localModelOperation = false;
      update();
    }
  }

  Future<void> _loadLocalModel(String id) async {
    final response = await _modelCommand('local.load', modelId: id);
    await saveConnection(Map<String, dynamic>.from(response['profile'] as Map));
  }

  Future<void> loadLocalModel(String id) async {
    if (busy || localModelOperation) return;
    localModelOperation = true;
    update();
    try {
      await _loadLocalModel(id);
    } finally {
      localModelOperation = false;
      update();
    }
  }

  Future<void> stopLocalModel() async {
    if (busy) return;
    final ownOperation = !localModelOperation;
    if (ownOperation) {
      localModelOperation = true;
      update();
    }
    try {
      await _modelCommand('local.stop');
    } finally {
      if (ownOperation) {
        localModelOperation = false;
        update();
      }
    }
  }

  Future<void> removeLocalModel(String id) async {
    if (busy || localModelOperation) return;
    localModelOperation = true;
    update();
    try {
      await _modelCommand('local.remove', modelId: id);
      await deleteConnection('gguf-$id');
    } finally {
      localModelOperation = false;
      update();
    }
  }

  void activateConnection(String id) {
    if (busy) return;
    final profile = connections.firstWhere((item) => item['id'] == id);
    activeConnectionId = id;
    config = {...profile};
    mode = 'rwkv';
    update();
    unawaited(savePreferences());
  }

  Future<void> saveConnection(Json profile, {bool activate = true}) async {
    if (busy) return;
    final value = Map<String, dynamic>.from(profile);
    value['id'] ??= DateTime.now().microsecondsSinceEpoch.toString();
    final id = value['id'] as String;
    final index = connections.indexWhere((item) => item['id'] == id);
    if (index < 0) {
      connections.add(value);
    } else {
      connections[index] = value;
    }
    if (activate) {
      activeConnectionId = id;
      config = {...value};
      mode = 'rwkv';
    }
    await savePreferences();
    if (_preferencesError.isNotEmpty) throw StateError(_preferencesError);
    update();
  }

  Future<void> installDefaultConnection(Json profile) async {
    final version = (profile['version'] as num? ?? 1).toInt();
    if (_defaultConnectionVersion >= version) return;
    final value = Map<String, dynamic>.from(profile);
    final index = connections.indexWhere((item) => item['id'] == value['id']);
    if (index < 0) {
      connections.add(value);
    } else {
      connections[index] = value;
    }
    activeConnectionId = value['id'] as String;
    config = {...value};
    mode = 'rwkv';
    _defaultConnectionVersion = version;
    await savePreferences();
    update();
  }

  Future<void> deleteConnection(String id) async {
    if (busy) return;
    connections.removeWhere((item) => item['id'] == id);
    try {
      await _secureStorage.delete(key: 'rwkvbuddy.connection.$id');
    } catch (_) {}
    if (activeConnectionId == id) {
      activeConnectionId = '';
      config = {
        'baseUrl': '',
        'model': '',
        'protocol': 'chat',
        'concurrency': 2,
      };
      mode = 'local';
    }
    await savePreferences();
    update();
  }

  File? get _preferences => dataRoot.isEmpty
      ? null
      : File(
          '${Directory(dataRoot).parent.path}${Platform.pathSeparator}settings.json',
        );
  Future<void> _loadPreferences() async {
    try {
      if (await _preferences?.exists() ?? false) {
        final saved = Map<String, dynamic>.from(
          jsonDecode(await _preferences!.readAsString()) as Map,
        );
        groupChat = saved['groupChat'] == true;
        expertLibrary = _maps(saved['expertLibrary']);
        if (saved['team'] is Map) {
          team = Map<String, dynamic>.from(saved['team'] as Map);
        }
        _defaultConnectionVersion =
            (saved['defaultConnectionVersion'] as num? ?? 0).toInt();
        if (saved['config'] is Map) {
          config.addAll(Map<String, dynamic>.from(saved['config'] as Map));
        }
        connections = _maps(saved['connections']);
        for (final profile in connections) {
          try {
            final secret = await _secureStorage.read(
              key: 'rwkvbuddy.connection.${profile['id']}',
            );
            if (secret != null) {
              profile.addAll(
                Map<String, dynamic>.from(jsonDecode(secret) as Map),
              );
            }
          } catch (_) {
            notice = '部分连接凭据无法从系统凭据库读取，请重新填写';
          }
        }
        activeConnectionId = saved['activeConnectionId'] as String? ?? '';
        if (connections.isEmpty &&
            (config['baseUrl'] as String? ?? '').isNotEmpty) {
          connections = [
            {'id': 'migrated', 'name': '默认远端连接', ...config},
          ];
          activeConnectionId = 'migrated';
        }
        final active = connections.where(
          (item) => item['id'] == activeConnectionId,
        );
        if (active.isNotEmpty) config = {...active.first};
        if (['rwkv', 'local'].contains(saved['mode'])) {
          mode = saved['mode'] as String;
        }
        final path = saved['workspace'] as String?;
        if (path != null && await Directory(path).exists()) workspace = path;
        update();
      }
    } catch (_) {
      /* Invalid preferences never prevent startup. */
    }
  }

  Future<void> savePreferences() {
    final file = _preferences;
    final safe = Map<String, dynamic>.from(config)
      ..removeWhere(
        (key, _) =>
            ['apiKey', 'accessId', 'accessSecret', 'headers'].contains(key),
      );
    final profiles = connections
        .map((profile) => Map<String, dynamic>.from(profile))
        .toList();
    final publicProfiles = profiles
        .map(
          (profile) => Map<String, dynamic>.from(profile)
            ..removeWhere(
              (key, _) => [
                'apiKey',
                'accessId',
                'accessSecret',
                'headers',
              ].contains(key),
            ),
        )
        .toList();
    final content = jsonEncode({
      'workspace': workspace,
      'groupChat': groupChat,
      'team': team,
      'expertLibrary': expertLibrary,
      'mode': mode,
      'config': safe,
      'connections': publicProfiles,
      'activeConnectionId': activeConnectionId,
      'defaultConnectionVersion': _defaultConnectionVersion,
    });
    return _preferencesWrite = _preferencesWrite.then((_) async {
      try {
        _preferencesError = '';
        for (final profile in profiles) {
          final secret = {
            for (final key in ['apiKey', 'accessId', 'accessSecret', 'headers'])
              key: profile[key],
          };
          await _secureStorage.write(
            key: 'rwkvbuddy.connection.${profile['id']}',
            value: jsonEncode(secret),
          );
        }
        await file?.writeAsString(content);
      } catch (_) {
        notice = '连接配置未能完整保存，请检查系统凭据库与数据目录权限';
        _preferencesError = notice;
        update();
      }
    });
  }

  Future<void> shutdown() async {
    final process = _process;
    if (process == null) return;
    _process = null;
    try {
      process.stdin.writeln(jsonEncode({'type': 'shutdown'}));
      await process.stdin.flush();
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      process.kill();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}
