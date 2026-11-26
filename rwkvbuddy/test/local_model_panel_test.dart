import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwkvbuddy/agent_controller.dart';
import 'package:rwkvbuddy/connection_settings.dart';

class ModelPicker extends FileSelectorPlatform {
  XFile? result;
  List<XTypeGroup>? types;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    types = acceptedTypeGroups;
    return result;
  }
}

class ModelAgent extends AgentController {
  ModelAgent() : super(autoConnect: false) {
    connected = true;
    localRuntimeAvailable = true;
  }
  String? imported;
  bool removed = false;
  final loaded = Completer<void>();
  @override
  Future<void> importLocalModel(String path) async {
    imported = path;
    localModelOperation = true;
    localModelState = {
      'status': 'loading',
      'modelId': 'one',
      'message': '正在加载测试模型',
    };
    localModels = [
      {'id': 'one', 'name': '中文 模型.gguf', 'bytes': 1024, 'path': path},
    ];
    update();
    try {
      await loaded.future;
    } finally {
      localModelOperation = false;
      update();
    }
  }

  @override
  Future<void> stopLocalModel() async {
    localModelState = {'status': 'idle', 'message': '模型已卸载'};
    loaded.complete();
    update();
  }

  @override
  Future<void> removeLocalModel(String id) async {
    removed = true;
    localModels = [];
    update();
  }
}

void main() {
  testWidgets(
    'local import filters GGUF files, shows loading, permits cancellation and preserves records',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = FileSelectorPlatform.instance;
      final picker = ModelPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final agent = ModelAgent();
      addTearDown(agent.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectionSettings(agent: agent)),
      );
      await tester.tap(find.text('本地模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-gguf')));
      await tester.pumpAndSettle();
      expect(agent.imported, isNull);
      picker.result = XFile('C:/模型/中文 模型.gguf');
      await tester.tap(find.byKey(const Key('import-gguf')));
      await tester.pump();
      expect(agent.imported, 'C:/模型/中文 模型.gguf');
      expect(picker.types!.single.extensions, ['gguf']);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-gguf')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('取消加载'));
      await tester.pumpAndSettle();
      expect(find.text('模型已卸载'), findsOneWidget);
      expect(find.text('加载并使用'), findsOneWidget);
      expect(find.text('中文 模型.gguf'), findsOneWidget);
      await tester.tap(find.text('移除记录'));
      await tester.pumpAndSettle();
      expect(agent.removed, isTrue);
      expect(find.text('中文 模型.gguf'), findsNothing);
    },
  );

  test(
    'unloaded imported model cannot send an inference request to an old port',
    () {
      final agent = AgentController(autoConnect: false);
      addTearDown(agent.dispose);
      agent.mode = 'rwkv';
      agent.config = {
        'localModelId': 'one',
        'baseUrl': 'http://127.0.0.1:1234/v1',
      };
      agent.start('你好');
      expect(agent.busy, isFalse);
      expect(agent.error, contains('加载此模型'));
    },
  );
}
