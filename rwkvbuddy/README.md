# TECNO Buddy

Windows / macOS 桌面文件助手。添加文件或选择资料目录，输入问题和处理要求，应用依次读取资料、请求模型分析、按需调用工具，交付中文回答及可下载的成果文件。

应用原名 RWKVBuddy，现更名为 TECNO Buddy。macOS 应用包为 `TECNO Buddy.app`，Windows 可执行文件为 `tecno_buddy.exe`；为兼容已有安装，内部包标识、历史数据目录和凭据键名继续沿用原标识。

每轮对话在同一页面展示处理过程与生成结果。文件读取、模型请求、工具调用可展开查看输入、输出和错误；支持直接提问、添加多个文件、下载成果和连续追问。历史任务保存在本机，重启后可以恢复。

桌面界面采用浅色侧栏与居中输入区，支持收起侧栏、通过任务类型或示例填入提问。输入框内可添加附件、切换模型和启用文件生成，下方可选择资料目录；支持 Ctrl / Cmd + Enter 发送。macOS 默认窗口为 1280 × 840，小窗口通过滚动和任务记录入口使用相同功能。

## 专家团群聊

点击侧栏“新建群聊”，或在输入框上方从“单助手”切换到“专家团群聊”。先在“模型服务”启用在线 API 或加载本地模型；本地规则演示不模拟专家发言。

当前重点支持多个 Agent 分析本地多个文件。在群聊输入框下方点击“添加文件”，一次多选 PDF、Word、Excel 或文本资料（也可继续追加），填写分析要求后发送。每位专家共享同一批文件的提取文本与来源标记，可以按需读取和检索原文，按职责对比差异、核对冲突并汇总结论。例如：“对比这些合同、预算表和会议记录，请各专家分析成本、交付要求和风险，主持人汇总并注明文件来源。”文件读取范围、大小限制及格式支持见下方说明。联网调研暂不接入；“本地文件”指资料来源，模型仍使用用户选择的在线 API 或本地模型。

- 默认团队包含策划、文案、设计、研发和主持人。点击团队名称可编辑名称、专家及职责，支持 1–6 位专家；主持人固定负责最后汇总。当前团队配置保存在本机，历史每轮保存当时的成员配置。
- 向全群提问时，专家按配置顺序分别执行模型请求和资料工具，每位成员能参考本轮前面已提交的讨论；主持人汇总共识、分歧与待确认事项。当前版本每轮每人发言一次，采用依次讨论；不包含自动管家派单或多个成员同时执行。
- 点击 `@` 按钮选择成员，也可输入 `@研发 请说明实现步骤`。指定成员时只调用该成员；`@全体` 或不指定成员则全员参与。名称后请加空格或中文分隔标点，支持指定多个成员。普通邮箱地址不作为成员指令。
- 群内显示各成员的头像、名称、提交状态、公开进度和生成中的回答。工具和模型的真实输入输出可展开“查看执行过程”。失败、取消和中断保留原状态，不将生成中的草稿作为已提交发言。
- 成果文件由本轮最后交付的成员统一生成，显示在其消息下，支持下载；默认由主持人交付，单独 `@` 专家时由该专家交付。支持导出整轮讨论记录。
- 历史可恢复成员消息、团队配置和文件。继续追问会带入最近对话及上一轮各成员的发言摘要；完整原始发言保留在历史。中途失败的专家会显示错误，其余成员可以继续，整轮标记部分完成；停止讨论会取消当前请求，不再调用后续成员。

多位成员共用当前所选的模型连接，分别使用各自职责和上下文，模型请求次数与耗时随参与人数增加。文件与工具能力沿用下文说明，不额外提供联网搜索、任意代码执行或图片生成。

## Windows 开发与运行

- Flutter 3.32.7 / Dart 3.8.1 已验证，SDK 约束为 `^3.8.1`。
- Visual Studio 2022：安装 **Desktop development with C++** 工作负载与 Windows SDK。
- Node.js 20.11+、Lua 5.4（`lua.exe` 与 `lua54.dll` 位于同一目录）。

```powershell
flutter doctor -v
flutter pub get
npm ci --prefix agent-service --omit=optional --ignore-scripts
python scripts/prepare-local-rwkv.py
powershell -ExecutionPolicy Bypass -File scripts/prepare-windows-runtime.ps1
flutter run -d windows
```

准备脚本从 PATH 复制运行时到 `agent-service/runtime/`，也可通过 `-NodePath`、`-LuaPath` 指定可执行文件。运行时目录不进入 Git；本地开发未准备运行时则尝试使用 PATH 中的 Node/Lua。

点击首页“经营与资金分析”，再点击“开始处理”，即可用随附样例验证完整流程。也可以选择自己的项目/文档目录，处理过程与结果会显示在同一轮对话中。

## 添加文件分析

点击输入框上方的“添加文件”，可多选并继续追加资料，在文件标签上移除不需要的文件。填写分析要求后点击“开始处理”。文件模式仅分析所选文件，不会同时扫描先前目录或自动使用内置样例。

- 支持 PDF、DOCX、XLSX、TXT、Markdown、CSV、TSV、JSON/JSONL、YAML 和常见代码文本。
- 每次最多 20 个文件、单文件 10 MB、原文件合计 20 MB；单文件提取文字最多 1 MB，总计 4 MB。UTF-8 和带 BOM 的 UTF-16 文本可直接读取。
- PDF 提取前 100 页的文字，保留页码；扫描件暂不支持 OCR。DOCX 提取正文与表格。XLSX 提取工作表名、单元格地址、值和公式缓存，不重算公式、不解析图表，日期可能显示为序列值。旧版 DOC/XLS 需先转换。
- 模型初始使用每文件前 12000 字符以内的片段，所有文件合计最多 60000 字符；截取范围会在报告中提示。完整提取文字、原文件路径与哈希保存在任务 `inputs/` 目录；原文件内容不会被修改。
- 文件读取失败会列明原因，其余文件继续分析，整体结果标为部分完成；全部失败则结束任务。
- 本地演示展示内容与数据摘录，不按任意表格推断业务口径；开放式分析可使用在线 API 或本地模型连接，效果取决于模型能力。文件片段发送到所配置的模型服务。

## 生成文件与继续修改

启用模型连接后，可通过输入框下方的“资料选项 → 添加文件”一次添加多个文件，或选择目录，再输入具体问题或处理要求。需要文件时直接输入“生成 Word 报告”“导出 Excel”等要求，模型根据本轮指令返回文件内容，程序实际生成文件并展示下载按钮。

- 例如：“对比这两份合同，列出差异和风险，生成 Word 报告”；“把这些销售表汇总为 Excel，增加毛利和合计”；“将文档预算改为 30000 元，生成修改后的 Word”。
- 支持生成 DOCX、XLSX、Markdown、TXT、CSV、JSON，最多 6 个文件。回答下方显示实际生成文件的下载按钮，可另存到指定位置。
- XLSX 必须提供包含工作表名称和二维单元格数据的 `sheets` 数组，不能将 Markdown 表格文字改名为 `.xlsx`。文件结构不合要求时，将具体校验错误反馈给模型，最多修正两次；保留失败及重试记录，仅在实际生成成功后展示下载。磁盘写入等系统错误直接报告，不请求模型修改文件结构。
- 文件格式修正过程中显示“正在自动修正”；同一文件后续生成成功后，原失败步骤标记“失败后已修复”，原始错误保留在调用详情。历史任务也会展示对应状态，最终失败仍显示错误。
- 生成结果保存在任务的 `outputs/` 目录。继续追问会读取原始资料及上一轮生成内容，例如“把刚才的报告缩短，并把预算改为 35000 元”；历史任务重新打开后也可下载或继续修改。
- 对话中实时显示“处理过程”，记录读取原文、模型分析、检索、计算和文件生成。每一步可展开实际输入输出，支持停止任务和导出处理记录。
- DOCX/XLSX 根据提取的正文或单元格内容生成新副本，不保留原件复杂排版、公式、图表、图片或宏。PDF 可作为文字输入，扫描件需先 OCR；当前不生成 PDF。修改原文需给出明确要求，原文件保留。
- 每轮最多补充 6 次资料工具调用；文件内容和输出长度也有限制，较大文档建议按章节或工作表拆分处理。模型仍需依据实际读取范围作答，不能保证任意文档全部内容已被处理。

## 模型服务与连续对话

点击左下角“模型服务”或顶部设置按钮，选择“在线 API”或“本地模型”。在线连接填写现有服务地址、协议、模型和凭据；本地模型点击“导入 GGUF 并加载”，选择文件后由原生 llama.cpp 直接加载并启用模型，再点击“开始对话”。支持取消加载、卸载释放内存、移除记录。导入保留原文件路径，不复制或删除模型；重启后可从列表重新加载。

本地推理通过标准输入输出调用随包的原生组件，不启动 HTTP 服务、不监听端口，也不做回环连接检测；无需普通用户安装 Python/PyTorch。支持兼容的 RWKV-7 GGUF 及其他文本 GGUF，Windows 默认 CPU、macOS 默认 Metal。开发环境需先准备运行时，步骤见 [本地 GGUF 模型](docs/local-rwkv.md)。Windows 已使用现有 Qwen2.5 0.5B GGUF 完成界面导入、加载、真实推理和卸载测试。RWKV `rwkv7-g1l-1.5b-Q4_K_M.gguf` 在 Apple M4 上小型验收通过 4/6 项，多步工具调用和成果文件交付仍不稳定；加载成功不代表业务准确率达标。

- 可保存多个连接，编辑、切换或删除。地址接受服务根地址、`/v1`、`/v1/models` 和完整推理接口地址，并自动规范化。
- “测试连接 / 获取模型”只验证模型列表接口；“测试生成”会真实请求一次模型并验证返回结果。支持从列表选择模型，也可手动填写。
- Chat Completions 连接支持“JSON 输出模式”，要求服务约束结构化响应。RWKV 模型默认开启，已有连接未配置此项也自动生效；其他在线模型默认关闭。局域网 IRWKV 服务 `rwkv7-g1m-preview-13.3b` 实测需开启此项，否则可能将思考文本混入正文，持续生成直到超时；不支持此选项的服务可手动关闭。
- 支持 Bearer Key/Password 和自定义请求头（例如 Cloudflare Access）；令牌与自定义请求头保存在系统安全存储中，公开的 `settings.json` 和任务记录不保存这些配置凭据。
- 在线 API 的“生成与并发参数 → 并发模型请求”支持填写正整数，例如 4、6、8，默认 2，不再限定为 1–3；实际可同时处理的数量由模型服务决定。本地模型当前固定 1 个；均可设置输出 Token 上限、温度。该参数控制请求容量，当前专家依次讨论的调度方式保持不变。CUDA 协议可填写服务器已经注册的 State ID 和 Adapter ID。暂不管理服务器上的模型、状态或适配器文件。
- 连接启用后可直接提问。完成后在同一输入框继续追问，复用已保存的资料快照和最近对话上下文；原文件移走后仍可使用快照。添加或移除附件、切换目录会在下一轮重新读取资料。
- 纯文字追问会更新本轮指令及其快照，保留历史对话和已生成文件；历史问题仅作背景，模型始终针对当前问题回答。常识问答可使用通用知识，文件分析仍以实际读取内容为依据。
- 点击“新建任务”清空本轮对话与附件选择，连接配置保留。

交互与远端配置设计参考 [RWKV-Agent](https://github.com/No-22-Github/RWKV-Agent)（参考版本 `f43ed65`），本项目使用 Flutter 与 Node 独立实现。当前交互使用统一的处理过程与生成结果视图。

## 在线 API、本地模型与演示

“在线 API”使用已有千问或其他 HTTP 模型服务；“本地模型”由原生组件直接读取此电脑上的 GGUF，两者复用相同的文件处理、工具调用和过程记录。切换连接只影响后续任务。导入的 GGUF 不使用 HTTP 地址或在线密钥，也不自动回退到在线服务。当前本地推理串行执行。

“本地演示”模式无需模型服务，使用固定规则读取资料、调用 Lua 核算台账并产出带来源的报告。此模式用于离线分析和验证流程，界面与报告会明确标注未调用模型；它不会按任意自然语言指令生成开放式分析。

在“模型服务”中启用连接后，模型根据用户要求决定是否读取更多内容、检索、计算或直接交付结果。每次工具结果会传回同一任务，继续请求模型，直到提交最终回答或达到调用上限。模型请求、工具失败及取消状态如实保存在记录中；响应因 Token 上限被截断时会精简重试，实际请求状态均保留；有可用回答但文件生成失败时显示部分完成。

接口协议：

- RWKV 协议：调用 `/v1/batch/completions`，使用 `contents` 请求和 `submit` JSON 返回格式。
- RWKV Lightning Python 协议：调用 `/v1/chat/completions`，使用 `contents` 原始续写请求，区别于标准聊天接口。
- Chat Completions 协议：调用 `/v1/chat/completions`，使用标准 `messages`，兼容提供该接口的服务。
- 在线模式支持环境变量 `FOREMAN_BASE_URL`、`FOREMAN_MODEL`、`FOREMAN_PASSWORD`、`FOREMAN_CF_ACCESS_CLIENT_ID`、`FOREMAN_CF_ACCESS_CLIENT_SECRET`；本地模型不读取这些在线配置。环境变量凭据不会写入应用偏好或任务记录；界面保存的凭据使用系统安全存储。

千问连接使用标准 Chat Completions。部署时复制 `agent-service/default-connection.example.json` 为 `agent-service/default-connection.json`，在本机填写服务器地址和 API Key；本地配置被 Git 忽略，不提交凭据。未创建本地配置时使用不含密钥的示例配置，也可在应用的“模型服务”中填写。首次启动会自动启用默认连接，已有其他连接保留。模型名称留空时会从 `/v1/models` 自动选择千问模型，配置中可手动覆盖。千问连接默认请求关闭思考模式，以便稳定返回结构化结果。后续手动选择的连接或演示模式会在重启后保留。

## 处理过程

- 单助手模式按执行顺序显示读取、分析、工具调用与文件生成；专家团群聊模式额外按成员显示独立发言和状态。两者均保留可展开的真实执行记录。
- 执行时在“进行中”左侧显示最近一次模型请求的平均生成速度（tokens/s），不含排队和等待首个 token 的时间。RWKV Chat 使用逐 token 记录计数；其他接口优先采用服务端用量，尚未提供计数时显示带“≈”的估算值，等待响应时显示“-- tokens/s”。速度与 token 数随调用记录保存。
- 附件读取显示文件名、提取行数和失败原因。远端项目分析先建立目录索引，再由模型按需浏览目录、查找文件、读取正文和搜索代码；每步显示真实参数、结果、错误与公开处理说明，避免重复展示整份上下文，不展示或编造模型内部思考。
- 工具调用默认显示读取路径和行号、原文摘录、检索词及匹配位置、计算结果或生成文件名；“调用详情”可展开实际输入、输出、错误和耗时。模型直接使用已有片段回答时，会明确说明本轮没有额外工具调用。
- 本地快照读取范围与提供给模型的片段范围分别展示。处理过程和回答随新增内容平滑向下跟随，草稿与最终回答在同一区域更新；手动上翻时暂停跟随，回到底部或点击顶部“跳到最新内容”后恢复。打开历史任务从处理记录开始。
- 模型报告 Token 截断时最多自动重试两次：临时提高输出额度（最多 8192 Token），逐步精简回答及文件内容，保留失败请求与重试记录。仅完整有效的 JSON 可交付；仍失败时标记中断草稿，不把错误报告作为生成结果。
- Chat Completions 响应不是有效 JSON 时，如尚未启用 JSON 输出模式，自动使用该模式重新请求一次，并保留失败和恢复记录；本轮后续工具请求继续使用 JSON 模式。仍不合格式或服务不支持时显示明确错误，不把思考文本、残缺 JSON 或普通文字当作成果。RWKV 默认在首次请求启用 JSON 模式；其他连接可手动开启以省去首次失败请求。
- 工具请求兼容 `tool` 名称字符串及 `{name, arguments}` 对象形式，参数为 JSON 字符串时先解码后交给原有校验和工具执行。过程记录保留模型原始输出，并显示规范化后的实际工具名称、参数及结果；未成功读取任何正文的项目任务不会交付已完成的分析结论。
- 在线模型单次请求限时 120 秒，本地模型为 600 秒，包含等待响应和流式接收；超时时停止请求并显示中文提示，保留已接收内容的过程记录。
- 模型流式生成时实时展示其公开的简短进度说明和回答草稿，草稿在完成前不作为最终结果；工具参数生成阶段标记为尚未执行。首个字符返回前显示请求阶段、等待时长及服务端尚未返回内容的提示；服务端如果整段返回，内容也只能在收到时展示。不会展示内部推理链或伪造进度。
- 项目工具支持 `list_directory`、`find_files`（`*` 通配）、`read_file`（路径与行号）、`search_text`（目录范围与文件分页）和计算。目录/搜索结果及长文件显式返回下一页位置，工具失败后模型可修正参数继续。单轮项目探索最多 24 次工具调用、10 分钟；普通附件保持 6 次工具调用。不提供联网搜索和任意命令执行。
- 问题开头可直接粘贴绝对项目路径；带空格的路径建议加引号。路径会实际验证，唯一匹配的目录尾部空格或末尾反斜杠可校正，失败时显示具体错误。
- 记录和结果一同保存，打开历史任务即可恢复；支持导出 JSON 处理记录、Markdown 结果。回答支持表格、列表和代码块。
- 处理说明、回答草稿和 Markdown 文件读取结果也支持标题、粗体、列表、表格与代码块排版。文件预览可切换原文；调用详情默认展示解码后的正文，原始 JSON 单独展开，复制保留原始内容。代码文件和目录列表使用等宽文本。
- 文件提取内容、模型输入输出和报告作为任务资料保存在本机；配置凭据不注入这些记录。

## 报告、历史与资料范围

- Windows 数据位置：`%APPDATA%\RWKVBuddy\runs\<任务 ID>\`，含 `run.json`、`events.jsonl`、`inputs.snapshot.json`、生成文件与 `report.md`。可用 `RWKVBUDDY_DATA_DIR` 覆盖任务存储目录。
- 结果支持复制和导出 Markdown；从左侧打开历史任务可恢复过程、回答及文件下载。
- 最近任务在鼠标悬停时显示“更多”菜单，支持置顶、取消置顶和删除。置顶状态保存在本机，重启后保留；删除需确认，会移除该任务的本地记录、快照和生成文件，不删除原始资料。运行中的任务需停止后才能删除。
- 分析只读访问工作区，不修改输入资料；正文按需缓存，保留哈希、引用行号和实际读取区间。项目索引和缓存随历史保存：原目录删除后仍能读取已缓存文件，尚未读取的文件需要原目录。模型模式会将实际工具结果发送到配置的模型服务。
- 远端项目索引最多 20000 项、16 层目录；正文单文件最多 1 MB、缓存合计 16 MB，每次读取最多 200 行/16000 字符，搜索每批最多 80 个文件/约 2 MB。跳过符号链接、隐藏/敏感文件和构建目录，Git 可用时排除忽略文件。仅已返回模型的行可作为引用，未读取部分不算通读。旧本地演示扫描仍为 240 个文件、总计 4 MB、单文件 256 KB。
- 固定财务核算仅用于本地演示，且资料必须位于所选目录根部的样例结构。远端模型按用户问题分析整个目录，不因子目录包含财务样例而切换任务。内置财务模板适配 `jobs/co-*/ledger.csv`、`shared/tax_rates.tsv` 和 `cash.jsonl` 样例格式，口径见 `agent-service/fixtures/README.md`。其他表格格式需增加适配。
- 当前版本提供分析问答、报告和受支持格式的文件生成，不执行模型生成的命令或任意代码。

## 构建与验证

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test agent-service/test/*.test.mjs
flutter test integration_test/desktop_flow_test.dart -d windows --no-pub
flutter test integration_test/gguf_import_test.dart -d windows --no-pub --dart-define=GGUF_TEST_PATH=C:/models/model.gguf
flutter build windows --release --no-pub
```

发布目录为 `build/windows/x64/runner/Release/`。分发整个目录，包括 DLL、`data` 与 `agent-service`，后者包含准备好的 Node/Lua 运行时，用户无需额外安装它们。

Flutter 通过 stdin/stdout JSONL 与 Node 服务通信；服务负责调度、资源并发限制、取消、模型流解析、任务及成果持久化。PDF 使用 PDF.js，DOCX/XLSX 使用 fflate 与 fast-xml-parser 提取，解析在有限时和内存限制的独立 Worker 中执行。Windows 发布包同时携带依赖和运行时，用户无需安装 Node/npm。Windows Job Object 负责在应用异常退出后回收子进程，正常退出则先取消任务并关闭服务。

参考项目分析见 [Windows 多 Agent 分析报告](docs/analysis/windows-multi-agent-report.zh-CN.md)。

## macOS builds

```sh
flutter pub get
npm ci --prefix agent-service --omit=optional --ignore-scripts
python3 scripts/prepare-macos-runtime.py
flutter run -d macos
flutter build macos --release
```

The preparation script downloads checksum-verified Node.js 22 LTS and Lua 5.4.8,
then prepares universal arm64/x86_64 runtimes. Xcode bundles the local service,
dependencies and runtimes into the application, so launching the app from Finder
does not depend on the working directory or a Homebrew installation.
The project and Runner deployment targets are set to macOS 14.6.
CocoaPods also raises older plugin deployment targets to 14.6 for Xcode 27.2.

Local credentials are excluded from the macOS app bundle. Configure a connection
in the app, or place a private `default-connection.json` in
`~/Library/Application Support/RWKVBuddy/` (same shape as the example profile).
`RWKVBUDDY_CONNECTION_FILE` can select another private profile. Project development
can continue to use the ignored `agent-service/default-connection.json`.
macOS history and generated files live in
`~/Library/Application Support/RWKVBuddy/runs/`.
Existing macOS installations with `~/.local/share/RWKVBuddy/runs/` continue to
use that directory so their history and connection preferences remain available.

This desktop build runs outside App Sandbox so its child service can process
selected local files and save results. It is intended for direct distribution;
Mac App Store sandboxing and notarization are separate deployment work.

The Flutter Assemble phase uses `macos/Flutter/tool_overrides/lipo` to
verify architectures individually. This works around Xcode 27.2 rejecting
Flutter 3.41's multi-architecture `lipo -verify_arch` invocation while
preserving both arm64 and x86_64 output. Other lipo operations pass through
to the selected Xcode toolchain.
