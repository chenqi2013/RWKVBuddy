# RWKVBuddy

Windows 桌面多角色协作工作台。添加自己的文件或选择资料目录，输入分析要求后，协调员分配工作，三个专家并行分析，质量复核员读取成果、核对来源并可要求定向修订，最后整合为可导出的中文报告。

界面采用对话、执行轨迹、分析报告和专家成果四个视图；支持直接提问、上传文件和连续追问。历史任务及轨迹保存在本机，重启后可以回放。没有联网搜索功能。

## Windows 开发与运行

- Flutter 3.32.7 / Dart 3.8.1 已验证，SDK 约束为 `^3.8.1`。
- Visual Studio 2022：安装 **Desktop development with C++** 工作负载与 Windows SDK。
- Node.js 20.11+、Lua 5.4（`lua.exe` 与 `lua54.dll` 位于同一目录）。

```powershell
flutter doctor -v
flutter pub get
npm ci --prefix agent-service --omit=optional --ignore-scripts
powershell -ExecutionPolicy Bypass -File scripts/prepare-windows-runtime.ps1
flutter run -d windows
```

准备脚本从 PATH 复制运行时到 `agent-service/runtime/`，也可通过 `-NodePath`、`-LuaPath` 指定可执行文件。运行时目录不进入 Git；本地开发未准备运行时则尝试使用 PATH 中的 Node/Lua。

点击首页“经营与资金分析”，再点击“开始协作”，即可用随附样例验证完整流程。也可以选择自己的项目/文档目录：角色自动调整为资料研究员、技术分析师和风险审计师。

## 添加文件分析

点击输入框上方的“添加文件”，可多选并继续追加资料，在文件标签上移除不需要的文件。填写分析要求后点击“开始协作”。文件模式仅分析所选文件，不会同时扫描先前目录或自动使用内置样例。

- 支持 PDF、DOCX、XLSX、TXT、Markdown、CSV、TSV、JSON/JSONL、YAML 和常见代码文本。
- 每次最多 20 个文件、单文件 10 MB、原文件合计 20 MB；单文件提取文字最多 1 MB，总计 4 MB。UTF-8 和带 BOM 的 UTF-16 文本可直接读取。
- PDF 提取前 100 页的文字，保留页码；扫描件暂不支持 OCR。DOCX 提取正文与表格。XLSX 提取工作表名、单元格地址、值和公式缓存，不重算公式、不解析图表，日期可能显示为序列值。旧版 DOC/XLS 需先转换。
- 每位专家初始使用每文件前 12000 字符以内的片段，所有文件合计最多 60000 字符；截取范围会在报告中提示。完整提取文字、原文件路径与哈希保存在任务 `inputs/` 目录；原文件内容不会被修改。
- 专家角色为资料分析师、数据分析师、风险审计师，随后由质量复核员复核。文件读取失败会列明原因，其余文件继续分析，整体结果标为部分完成；全部失败则结束任务。
- 本地模式展示内容与数据摘录，不按任意表格推断业务口径；要根据用户指令进行开放式分析，请使用默认千问连接或其他远端模型。模型模式会向所配置的服务发送文件片段。

## 远端连接与连续对话

点击左下角“远端连接”或顶部设置按钮，新建连接并填写名称、地址、协议、模型和凭据。

- 可保存多个连接，编辑、切换或删除。地址接受服务根地址、`/v1`、`/v1/models` 和完整推理接口地址，并自动规范化。
- “测试连接 / 获取模型”只验证模型列表接口；“测试生成”会真实请求一次模型并验证返回结果。支持从列表选择模型，也可手动填写。
- 支持 Bearer Key/Password 和自定义请求头（例如 Cloudflare Access）；令牌与自定义请求头保存在系统安全存储中，公开的 `settings.json` 和任务记录不保存这些配置凭据。
- 可设置 1–3 个并发请求、输出 Token 上限、温度；CUDA 协议可填写服务器已经注册的 State ID 和 Adapter ID。暂不管理服务器上的模型、状态或适配器文件。
- 连接启用后可直接提问。完成后在同一输入框继续追问，复用已保存的资料快照和最近对话上下文；原文件移走后仍可使用快照。添加或移除附件、切换目录会在下一轮重新读取资料。
- 点击“新建任务”清空本轮对话与附件选择，连接配置保留。

交互与远端配置设计参考 [RWKV-Agent](https://github.com/No-22-Github/RWKV-Agent)（参考版本 `f43ed65`），本项目使用 Flutter 与 Node 独立实现。保留横向专家状态，不展示右侧专家团队竖栏。

## 两种执行模式

“本地演示”模式无需模型服务，使用固定规则读取资料、并行调用 Lua 核算台账并产出带来源的报告。此模式用于离线分析和验证流程，界面与报告会明确标注未调用模型；它不会按任意自然语言指令生成开放式分析。

在“远端连接”中启用配置后，各专家使用独立模型请求，复核员另开会话审阅实际成果。支持 1–3 个并发模型请求；三个专家任务并发调度，财务核算工具最多同时执行两个进程。复核不通过时，仅重跑被要求修订的专家，最多一轮。模型请求失败会保留失败状态和已有成果，并输出部分报告。

接口协议：

- RWKV 协议：调用 `/v1/batch/completions`，使用 `contents` 请求和 `submit` JSON 返回格式。
- RWKV Lightning Python 协议：调用 `/v1/chat/completions`，使用 `contents` 原始续写请求，区别于标准聊天接口。
- Chat Completions 协议：调用 `/v1/chat/completions`，使用标准 `messages`，兼容提供该接口的服务。
- 支持环境变量 `FOREMAN_BASE_URL`、`FOREMAN_MODEL`、`FOREMAN_PASSWORD`、`FOREMAN_CF_ACCESS_CLIENT_ID`、`FOREMAN_CF_ACCESS_CLIENT_SECRET`。环境变量凭据不会写入应用偏好或任务记录；界面保存的凭据使用系统安全存储。

千问连接使用标准 Chat Completions。部署时复制 `agent-service/default-connection.example.json` 为 `agent-service/default-connection.json`，在本机填写服务器地址和 API Key；本地配置被 Git 忽略，不提交凭据。未创建本地配置时使用不含密钥的示例配置，也可在应用的“远端连接”中填写。首次启动会自动启用默认连接，已有其他连接保留。模型名称留空时会从 `/v1/models` 自动选择千问模型，配置中可手动覆盖。千问连接默认请求关闭思考模式，以便稳定返回结构化专家成果。后续手动选择的连接或演示模式会在重启后保留。

## 执行轨迹

- “执行轨迹”显示每个专家的请求与工具时间线，可按角色、工具、模型或失败步骤筛选。请求耗时包含模型资源排队时间。
- 每一步可展开查看实际输入、结果、错误、开始与完成时间、耗时；模型流式输出显示为尚未校验的响应，不将它称为内部思考过程。
- 专家可在三次工具调用额度内读取快照的指定文本行、检索资料内文字或做四则计算，然后提交带证据的成果；不提供联网搜索和任意命令执行。
- 轨迹与专家修订版本一同保存，打开历史任务即可恢复；支持导出 JSON。报告和回答支持 Markdown 表格、列表和代码块。
- 文件提取内容、模型输入输出和报告作为任务资料保存在本机；配置凭据不注入这些记录。

## 报告、历史与资料范围

- Windows 数据位置：`%APPDATA%\RWKVBuddy\runs\<任务 ID>\`，含 `run.json`、`events.jsonl`、`inputs.snapshot.json`、专家版本成果与 `report.md`。可用 `RWKVBUDDY_DATA_DIR` 覆盖任务存储目录。
- 报告支持复制和导出 Markdown；可以点击专家卡片查看成果，或从左侧打开历史任务。
- 分析基于只读工作区快照，附文件哈希与行号，不修改输入资料；模型模式会将所选资料片段发送到配置的模型服务。
- 扫描限制为 240 个文本文件、总计 4 MB、单文件 256 KB，跳过符号链接、隐藏/敏感文件和构建目录；超出范围会在结果中提示。通用研究使用文件片段，不能替代完整代码审查。
- 内置财务模板适配 `jobs/co-*/ledger.csv`、`shared/tax_rates.tsv` 和 `cash.jsonl` 样例格式，口径见 `agent-service/fixtures/README.md`。其他表格格式需增加适配。
- 当前版本交付分析报告，不执行模型生成的命令或任意代码。专家职责由财务/通用资料模板确定。

## 构建与验证

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test agent-service/test/*.test.mjs
flutter test integration_test/desktop_flow_test.dart -d windows --no-pub
flutter build windows --release --no-pub
```

发布目录为 `build/windows/x64/runner/Release/`。分发整个目录，包括 DLL、`data` 与 `agent-service`，后者包含准备好的 Node/Lua 运行时，用户无需额外安装它们。

Flutter 通过 stdin/stdout JSONL 与 Node 服务通信；服务负责调度、资源并发限制、取消、模型流解析、独立成果持久化和报告整合。PDF 使用 PDF.js，DOCX/XLSX 使用 fflate 与 fast-xml-parser 提取，解析在有限时和内存限制的独立 Worker 中执行。Windows 发布包同时携带依赖和运行时，用户无需安装 Node/npm。Windows Job Object 负责在应用异常退出后回收子进程，正常退出则先取消任务并关闭服务。

参考项目分析见 [Windows 多 Agent 分析报告](docs/analysis/windows-multi-agent-report.zh-CN.md)。

## macOS builds

Run `flutter build macos --debug` for development or
`flutter build macos --release` for a universal macOS application.
The project and Runner deployment targets are set to macOS 14.6.

The Flutter Assemble phase uses `macos/Flutter/tool_overrides/lipo` to
verify architectures individually. This works around Xcode 27.2 rejecting
Flutter 3.41's multi-architecture `lipo -verify_arch` invocation while
preserving both arm64 and x86_64 output. Other lipo operations pass through
to the selected Xcode toolchain.
