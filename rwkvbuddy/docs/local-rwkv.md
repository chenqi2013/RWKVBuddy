# Windows / macOS 本地 RWKV-7 GGUF

本地模型改用用户提供的 `rwkv7-g1l-1.5b-Q4_K_M.gguf`，由原生 llama.cpp 加载。原先的 PyTorch / `.pth` 服务和下载脚本已移除，无需安装 torch 或 rwkv Python 库。Python 3.10+ 仅用于准备和启动脚本，使用标准库；实际推理由 C++ 进程执行。

本地模型服务仍需单独启动，应用不自动下载权重或启动服务。“本地演示”仍是固定规则流程，与模型推理不同。当前只支持 Windows 和 macOS。

## 运行时准备

使用固定的 llama.cpp 提交 `e4b620af19f02960dea7a3a81de7c5805aa3a333`，包含 RWKV-7 支持。需要 Python 3.10+、Git、CMake 3.19+ 和 C++ 编译工具。

| 平台 | 编译环境 | 默认推理后端 |
| --- | --- | --- |
| Windows x64 / ARM64 | Visual Studio 2022 Build Tools，安装对应架构的“使用 C++ 的桌面开发”和 Windows SDK | CPU |
| macOS Apple Silicon / Intel | Xcode 与 Metal 编译工具 | Metal；可指定 CPU |

在项目根目录执行，Windows 使用 `python`，macOS 使用 `python3`：

```powershell
python scripts/prepare-local-rwkv.py
```

```sh
python3 scripts/prepare-local-rwkv.py
```

脚本拉取固定源码，编译当前机器架构的 `llama-server`，静态链接 llama.cpp/ggml，并将二进制、许可证和版本信息放在被 Git 忽略的 `agent-service/runtime/llama/<平台-架构>/`。首次准备需要联网；生成后的推理服务使用本地模型并启用离线模式。Windows 构建使用 CPU，不需要 CUDA。macOS 编译并嵌入 Metal 内核。

运行时当前独立使用，不随 Flutter 安装包自动提供；分发时须另行提供对应平台的运行时和 GGUF。可以用 `--source <已有的固定版本 llama.cpp 目录>` 复用源码，或用 `--jobs 4` 限制编译并行度。

## 启动服务

保留现有模型文件位置即可，`--model` 接受完整路径；也可以将模型放到被 Git 忽略的 `local-models/` 目录。不要将权重提交到 Git。

Windows PowerShell：

```powershell
python agent-service/local-model/server.py --model "C:\模型\rwkv7-g1l-1.5b-Q4_K_M.gguf"
```

macOS：

```sh
python3 agent-service/local-model/server.py --model "local-models/rwkv7-g1l-1.5b-Q4_K_M.gguf"
```

等待 llama.cpp 日志显示 `model loaded` 和 `listening on http://127.0.0.1:8099`。启动脚本的 `Loading GGUF` 只表示开始加载；模型加载失败时进程会返回非零退出码。

常用参数：

| 参数 | 默认值 / 用途 |
| --- | --- |
| `--port` | `8099` |
| `--context-limit` | `8192`；映射到 llama.cpp 的 `--ctx-size`，允许 512–65536 |
| `--threads` | 不超过 8 的 CPU 线程数 |
| `--gpu-layers` | macOS 为 `-1`，Windows 为 `0`；macOS Metal 不可用时可设 `0` 使用 CPU |
| `--server` | 指定其他兼容版本的 `llama-server` 可执行文件 |

服务固定绑定 `127.0.0.1`，并发槽为 1。使用 GGUF 自带的分词器和 Jinja 聊天模板，默认关闭思考模式，启用单独的 reasoning 字段解析。应用忽略 reasoning 字段，只显示公开进度和回答。关闭上下文滑动和跨请求提示词缓存；超过上下文预算会报错，输出达到 Token 上限会标记截断，由应用的恢复逻辑处理。关闭内置网页，启动时清除外部 `LLAMA_ARG_*` 参数，避免环境变量覆盖运行设置。

## 应用连接

进入“模型服务 → 本地模型 → 新建连接”，默认值为：

| 配置 | 值 |
| --- | --- |
| 地址 | `http://127.0.0.1:8099/v1` |
| 接口协议 | OpenAI 兼容 · Chat Completions |
| 模型名称 | `rwkv7-g1l-1.5b-Q4_K_M`，取所加载 GGUF 文件名去除扩展名 |
| API Key | 无需填写 |
| 并发 | 固定 1 |
| 输出 Token 上限 | `1024`，可按任务调整 |

旧 `.pth` 连接不会被自动覆盖，请新建 GGUF 连接，或修改旧连接的协议和模型名称。在线 API 连接继续独立保留。先点“测试连接 / 获取模型”，再点“测试生成”，最后“保存并使用”。本地 Chat 请求启用 `response_format: {"type":"json_object"}`，约束 JSON 语法；这不能保证数据、工具参数或业务结论正确。

客户端仅允许回环地址，不沿用在线连接的密钥和请求头，不跟随重定向，不自动切换在线模型。文件读取、工具调用、流式进度和成果交付继续使用应用原有流程。

## 实测结果与验收

2026-11-19 在 Apple M4、macOS 26.6.2 上实际加载了用户提供的完整 GGUF，并用准备脚本编译的原生运行时进行验收：

| 项目 | 结果 |
| --- | --- |
| 格式 / 架构 | GGUF v3，RWKV-7，24 层、2048 维，约 15.28 亿参数 |
| 量化 | Q4_K_M，约 977 MiB 文件 |
| SHA-256 | `fbe32c9df26130d8df18bc452f4c30ea36da53806c1e4f722c65e6cc18c74ac3` |
| 加载、模型列表、SSE 流式生成 | 通过 |
| 严格 JSON、合同字段提取、工具请求、缺失字段返回 null | 4 项通过 |
| 根据工具结果填入最终回答 | 失败，照抄了示例中的“计算结果” |
| 读取附件 → 计算工具 → 生成 JSON 文件 | 失败，重复调用工具，未完成最终文件交付 |

两轮实际验收均为 **4/6**。其中一次完整流程正确调用了 `36*12`，但仍未结束工具循环；另一次出现错误参数 `6*12`。错误没有被掩盖，应用保留实际调用记录并标记失败/部分完成。简单短问答 `36×12` 能回答 `432`；这不能证明它能可靠完成复杂 Agent 任务。小型探针首个公开字符约 0.2–0.6 秒，短回答生成约 65–75 Token/s，仅供此开发机参考。

Windows 和 Intel Mac 的启动参数与架构选择有自动化覆盖，尚未在对应实机上加载权重验证速度、内存和推理质量。不能把 Apple M4 的结果视为所有平台的性能保证。

重新运行真实模型验收：

```sh
node scripts/evaluate-local-rwkv.mjs --workflow
```

局域网部署使用“在线 API”连接类型。可通过同一脚本对比，显式启用 `--api`，不会放宽本机模式的回环地址限制：

```sh
node scripts/evaluate-local-rwkv.mjs http://192.168.0.115:8104/v1 --api --json-output --workflow
```

`--json-output` 请求服务提供 JSON 输出约束。界面中的对应选项为“JSON 输出模式”；RWKV Chat 连接默认开启，包括未保存此字段的旧连接，服务不支持时可显式关闭。`rwkv7-g1m-preview-13.3b` 未启用时可能持续输出而在 120 秒后超时。API 验收使用空凭据，不读取其他服务的环境变量密钥；如接口要求鉴权，需要另行接入凭据。脚本只使用合成合同资料，不发送用户的实际文件。

记录写入 `build/model-evaluation/rwkv-<时间戳>/results.json`，包含实际响应、耗时及完整任务目录；任何用例失败会返回非零退出码。仍需使用实际用户文档验证复杂表格、项目分析、多轮修改、引用准确性和长上下文质量。

回归测试：

```sh
python3 -m unittest discover -s agent-service/local-model -p test_server.py -v
npm test --prefix agent-service
flutter test --no-pub
```

启动器测试覆盖 Windows/macOS 架构、路径与参数校验、拒绝 `.pth`，不将模拟测试视为真实模型能力证据。原生服务接口和推理行为由上述实机验收补充验证。
