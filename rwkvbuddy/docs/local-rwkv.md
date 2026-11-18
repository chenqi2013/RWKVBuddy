# Windows 本地 RWKV 模型服务

应用提供“在线 API”和“本地模型”两种模型连接，入口是左下角或顶部的“模型服务”。在线连接继续使用现有千问服务；本地连接将相同的文件分析、工具调用、流式过程和文件生成请求发送到此电脑上的 Python RWKV 服务。本地服务需单独安装、启动，当前不是应用内一键启动。

“本地演示”仍是无需模型的固定规则流程，与本地模型推理不同。

## 指定权重的评估结论

目前可作为本地实验模型接入，尚不能认定满足现有全部业务需求。官方 G1 系列提供 JSON 函数调用模板，但模板支持不等于复杂任务执行可靠。短文本摘要、简单字段抽取值得试验；多文件对比、多步工具选择、可靠引用、复杂 Word/Excel 生成及长上下文召回都需要真实权重验收。

本次确认了仓库信息和 checkpoint 张量结构，并通过同结构的小型合成权重验证 CPU 推理代码。**没有完整下载或加载指定权重，没有测出它的真实回答质量、首字耗时或生成速度。** HTTP/界面回归使用模拟后端，不作为模型能力证据。

| 项目 | 核实结果 |
| --- | --- |
| 仓库 / 文件 | `BlinkDL/temp-latest-training-models` / `rwkv-g1m-1b-temp-6629-ctx65536.pth` |
| 固定版本 | `70e6d2849493a08a5556944b73b57ba85788c5c0` |
| 下载大小 | 3,055,444,605 字节，约 3.06 GB / 2.85 GiB |
| SHA-256 | `53193f7dfa65cad5edc3ec7c664a14f40f70f71338e46af4e9e9d21608affb6d` |
| 实际参数 | 1,527,668,736，约 15.28 亿参数；不能按文件名中的 1B 估算占用 |
| 结构 | RWKV-7，24 层，2048 维，65536 词表；没有 DeepEmbed 张量 |
| 上下文 | 文件名标称 65536；本项目尚未验证该长度的准确率和速度 |
| 元数据检查 | 仅读取约 2 MB 的远端 checkpoint 元数据，没有下载全部权重 |

检查时的开发机为 i7-13700H、16 GB 内存、Intel Iris Xe，无 NVIDIA/CUDA；当时可用内存不足 2 GB。CPU fp32 仅权重就约 5.69 GiB，加载/转换、激活、运行状态还需额外内存，因此未尝试完整加载以免耗尽内存。建议先释放至少 8–10 GiB 可用内存再试，实际峰值仍需测量；16 GB 整机内存不能直接视为满足条件。当前 CPU 路径不使用 Intel 核显加速。

## 安装和下载

以下命令均在项目根目录执行，使用 Python 3.11–3.13，预留至少 10 GB 磁盘空间。Python 与 PyTorch 独立于 Flutter/Node，不随桌面应用自动安装。首次安装依赖和下载权重需要网络，服务加载本地权重后不联网。

```powershell
python -m venv agent-service/local-model/.venv
agent-service/local-model/.venv/Scripts/python.exe -m pip install --upgrade pip
agent-service/local-model/.venv/Scripts/python.exe -m pip install torch==2.6.0 --index-url https://download.pytorch.org/whl/cpu
agent-service/local-model/.venv/Scripts/python.exe -m pip install -r agent-service/local-model/requirements.txt
python scripts/download-local-rwkv.py
```

下载脚本固定上述版本，支持 `.pth.part` 断点续传，完成后检查大小和 SHA-256，再重命名为 `.pth` 并记录来源。权重位于被 Git 忽略的 `local-models/`。中断后重新运行同一命令；校验失败的残片需要手动移走后重试。官方源不可达时，可显式选择第三方镜像，校验值保持相同：

```powershell
python scripts/download-local-rwkv.py --mirror
```

## 启动并连接

```powershell
agent-service/local-model/.venv/Scripts/python.exe agent-service/local-model/server.py --model local-models/rwkv-g1m-1b-temp-6629-ctx65536.pth --strategy "cpu fp32" --threads 4 --context-limit 8192
```

等终端显示 `Ready: http://127.0.0.1:8099/v1` 后，在应用中进入“模型服务 → 本地模型 → 新建连接”。页面会预填：

| 配置 | 值 |
| --- | --- |
| 运行模式 | 本地模型 |
| 服务地址 | `http://127.0.0.1:8099/v1` |
| 接口协议 | RWKV Lightning Python |
| 模型名称 | `rwkv-g1m-1b-temp-6629-ctx65536` |
| API Key | 无需填写 |
| 模型并发 | 固定 1 |
| 默认输出上限 | 1024 Token |

依次点击“测试连接 / 获取模型”“测试生成”，再“保存并使用”。列表成功仅说明服务可达，生成测试才会实际推理；CPU 首次生成可能较慢。启动报错或内存不足时保留在线 API 连接供手动切换。

服务只绑定 `127.0.0.1`，支持 `/v1/models`、`/health` 和 `/v1/chat/completions`（`contents` 原始续写或标准文本 `messages`，含 SSE）。客户端本地模式仅允许回环地址，不沿用在线连接的环境变量地址、密钥或自定义请求头，也不跟随 HTTP 重定向，不自动回退云端。当前整个文件任务的已有超时/调用次数上限仍有效；本地单次模型请求最多等待 600 秒。

一个服务实例只执行一个推理请求，额外请求返回 429；应用为本地模型固定串行调度。任务仍可使用现有文件读取、计算、成果生成和轨迹逻辑，但此部署不代表多个模型角色能在这台电脑并行推理。推理请求之间不共享状态；停止流式任务后在当前 forward 返回时结束推理并释放资源。

默认本地上下文预算为 8192 Token，包含输入和预留输出；超过预算直接报错，不静默截断原文。可用 `--context-limit 16384` 等增加预算，最大 65536，但要重新测量耗时与质量。应用当前每文件/总片段字符限额仍有效，文件名中的 64K 不代表应用会自动读完所有资料。

## 真实模型验收

服务加载真实权重后运行：

```powershell
node scripts/evaluate-local-rwkv.mjs
# 同时执行真实附件读取 → 计算工具 → JSON 成果文件流程
node scripts/evaluate-local-rwkv.mjs --workflow
```

默认五项检查严格 JSON、字段抽取、计算工具请求、工具结果使用、未知事实不猜测。记录包括响应、首字等待时间和总耗时，保存到 `build/model-evaluation/`，失败以非零状态退出。`--workflow` 通过应用相同的 AgentRun 执行受控 TXT 附件任务，检查实际 calculator 轨迹与生成 JSON 内容。这些小样本通过也不构成完整业务验收。

后续至少需用实际用户资料检查：多文件交叉比对、连续追问修改已有文件、Word/Excel 可打开且数据准确、引用对应原文、超过首段的事实召回、长任务取消后再次生成。对比在线千问的正确率、首字等待、完成耗时和内存峰值，建议每类至少重复 5 次，达标阈值按用户可接受的等待时间制定。当前没有这些真实权重结果。

服务回归测试（不加载真实模型）：

```powershell
python -m unittest discover -s agent-service/local-model -p test_server.py -v
```

## 依据

- [用户指定模型](https://huggingface.co/BlinkDL/temp-latest-training-models/blob/main/rwkv-g1m-1b-temp-6629-ctx65536.pth)
- [固定版本仓库](https://huggingface.co/BlinkDL/temp-latest-training-models/tree/70e6d2849493a08a5556944b73b57ba85788c5c0)
- [官方 G1 系列聊天与函数调用模板](https://github.com/BlinkDL/RWKV-LM/blob/main/RWKV-v7/RWKV7-G1x-templates.txt)
- [RWKV Python 运行库](https://pypi.org/project/rwkv/0.8.32/)
- [参考项目 RWKV-Agent](https://github.com/No-22-Github/RWKV-Agent)：其本地推理依赖 macOS MLX，本项目 Windows 服务采用独立 Python/PyTorch 路径。
