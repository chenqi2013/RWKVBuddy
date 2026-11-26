# Windows / macOS 原生 GGUF 推理

应用导入 GGUF 后，由随包的 `rwkvbuddy-inference` 原生组件直接读取权重并调用 llama.cpp。加载、生成、流式输出和取消均使用标准输入输出 JSONL，不启动 HTTP 服务、不监听端口、不访问 `/health` 或 `/v1/models`。在线 API 使用原有 HTTP 接口。

原生组件是独立的本机子进程，用于隔离模型内存和推理异常，并非 Flutter 进程内的 FFI。模型持续保留在内存中，下一次请求无需重新加载。退出应用或点击卸载会停止该进程并释放内存。普通用户不需要 Python、PyTorch 或额外启动命令。

## 使用方式

1. 打开“模型服务 → 本地模型”，点击“导入 GGUF 并加载”。本地页无需创建 API 连接或填写地址。
2. 选择兼容的聊天 / Instruct `.gguf` 文件。导入只记录原路径，不复制权重，请勿移动或删除原文件。
3. 等待读取权重和初始化上下文。原生组件确认模型与上下文就绪后，界面显示“模型已加载，可以开始对话”。
4. 点击“开始对话”使用现有问答、附件分析、工具和成果输出流程。
5. 加载期间可取消；“卸载模型 / 释放内存”停止推理进程；“移除记录”保留原文件。

记录保存在用户数据目录 `runs/local-models.json`。重启后保留列表，点击“加载并使用”恢复；旧版导入连接也会在重新加载时更新为原生连接。没有加载的模型会在发出请求前拦截，不自动回退在线模型。

当前使用 8192 Token 上下文、4 个 CPU 线程、单个推理槽。Windows 使用 CPU，macOS 使用 Metal。请求串行处理，每次清空上次的推理状态，由应用提供所需对话背景。使用 GGUF 自带的聊天模板，关闭思考输出，并通过 JSON 语法约束返回结构化结果。超过上下文或输出上限会明确报错。取消生成会等候原生确认；若取消无响应，将停止模型，要求重新加载。

GGUF 是容器格式，架构、量化、分词器和聊天模板须与固定版本的 llama.cpp 兼容。损坏、不支持或没有聊天模板的模型会显示错误详情。加载成功不代表模型能准确完成复杂 Agent 任务。

## 准备运行时和发布包

需要 Python 3.10+、Git、CMake 3.19+，Windows 使用 Visual Studio 2022 C++ 桌面开发工具，macOS 使用 Xcode 与 Metal 工具。

在项目根目录运行（macOS 使用 `python3`）：

```powershell
python scripts/prepare-local-rwkv.py
flutter build windows --release --no-pub
```

准备脚本固定 llama.cpp 提交 `e4b620af19f02960dea7a3a81de7c5805aa3a333`，编译 `agent-service/local-model/native/`，静态链接 llama.cpp / ggml。二进制、许可证、版本及通信方式记录在被 Git 忽略的 `agent-service/runtime/llama/<平台-架构>/`。可通过 `--source <源码目录>` 复用该版本源码，或通过 `--jobs 4` 限制编译并行度。

Windows 发布包包含 `rwkvbuddy-inference.exe`，构建缺少原生运行时会失败；打包会排除旧 `llama-server`。macOS 打包复制并签名原生组件。首次准备源码需要联网，实际本地加载与推理无需网络。分发完整 Release 目录，不能只复制主程序；GGUF 由用户选择。

## 验证

2026-11-25 在 Windows 使用 Qwen2.5 0.5B Instruct Q4_K_M 实测：直接加载、流式 JSON、中文输出、`36×12 = 432`、取消生成后再次生成、卸载均通过；测试禁用了全局 HTTP fetch，整个本地流程仍可完成。

```powershell
npm test --prefix agent-service
flutter test --no-pub
$env:GGUF_TEST_PATH='C:/models/qwen2.5-0.5b-instruct-q4_k_m.gguf'
node --test agent-service/test/native-gguf.test.mjs
flutter test integration_test/gguf_import_test.dart -d windows --no-pub --dart-define=GGUF_TEST_PATH=C:/models/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

Node 回归覆盖加载握手、取消、队列复用、异常退出、超时、原文件保留和无 HTTP 的 Provider 调用；Flutter 集成测试覆盖界面导入、真实生成测试、对话和卸载。

复杂工具能力可用原生模型验收脚本复测：

```powershell
node scripts/evaluate-local-rwkv.mjs --model C:/models/model.gguf --workflow
```

在线 API 比较需显式指定地址与 `--api`：

```powershell
node scripts/evaluate-local-rwkv.mjs http://192.168.0.115:8104/v1 --api --json-output --workflow
```

结果写入 `build/model-evaluation/rwkv-<时间戳>/results.json`，失败返回非零退出码。仅使用合成合同资料，不发送用户实际文件。

此前在 Apple M4 上对 RWKV-7 1.5B Q4_K_M 的旧 HTTP 路径验收为 4/6 项，复杂工具循环和文件交付未通过；那是历史模型能力记录，不能作为本次原生路径或其他电脑的验收结果。macOS 原生路径尚需实机验证。

仓库中的旧 `server.py` 仅保留为历史手动服务工具，应用和准备脚本不再使用，发布包也不包含它。已有手动本机 API 连接仍可兼容使用，但导入 GGUF 统一使用原生管道通信。
