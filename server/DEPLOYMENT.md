# 后端运行与部署

以下命令均在 `E:\code\HarmonyOS-CampusAssistant\server` 目录执行。保留现有 `.env`，不要用示例配置覆盖密钥。升级后需重启原后端进程。

## 单进程与本地识别

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe prepare_models.py
.\.venv\Scripts\python.exe run.py --host 0.0.0.0 --port 8000 --workers 1
```

现有开发环境已下载 `data/models/whisper-small`，无需再次下载。新环境需要能够访问 Hugging Face；下载失败时可在可信网络重试，或自行设置可信的 `HF_ENDPOINT`。运行推理只读取本地模型。

`.env` 设置 `ASR_PROVIDER=local`、`DOCUMENT_OCR_PROVIDER=local`。Whisper 使用 CPU int8，默认 4 线程；RapidOCR 使用本地 ONNX。健康检查为 `/health`，接口文档为 `/docs`。`asr_configured` 表示配置/模型文件存在，不代表课堂准确率验收。中文语音和图片已经实际识别；短分片可能产生同音词误识别，系统会使用课程名、课时名和已发布提纲标题提供术语提示。

华为 SIS 仍可选择 `ASR_PROVIDER=huawei_sis`，但现有配置请求返回 `401 APIG.0301`，需要校验区域、项目及 AK/SK 权限；当前使用本地识别。不要选择 `mock` 用于真实转写。LLM 和 Embedding 仍需要各自的在线服务配置。

## 同机多进程

所有 API 进程必须使用同一数据库、相同的绝对数据目录和同一主机文件锁。默认 SQLite 开启 WAL 与 30 秒 busy timeout。学习小组、导入和维护各选举一个调度进程，学习小组还使用房间锁防止重复处理。该方案不支持多台主机或不共享锁目录的容器。

启用 Embedding 时，先停止正在直接使用 `data/chroma` 的 API 实例并备份数据库和数据目录，再启动独立 Chroma 服务。不要让嵌入式 Chroma 与 HTTP 服务同时访问同一目录。

终端一：

```powershell
.\.venv\Scripts\chroma.exe run --path ./data/chroma --host 127.0.0.1 --port 8002
```

在 `.env` 设置 `CHROMA_HOST=127.0.0.1`、`CHROMA_PORT=8002`、`CHROMA_SSL=false`。终端二：

```powershell
.\.venv\Scripts\python.exe run.py --host 0.0.0.0 --port 8000 --workers 2
```

必须使用 `run.py` 启动多个 worker，它会传递进程数供启动检查；直接调用 `uvicorn --workers` 不受此检查保护。Chroma 只监听本机，客户端访问 FastAPI。迁移或变更 Embedding 模型后，在知识库页面按提示重建索引。

每个 API 进程会各自加载 Whisper 模型，增加进程数会增加内存和 CPU 竞争，普通开发机建议先用 1 个。`MEETING_WORKERS=4` 限制后台房间并发，`DOCUMENT_JOB_WORKERS=2` 限制同时解析数。已验证 2 个真实 API worker、共享 Chroma、并发注册/加入学习小组/检索；测试 Embedding 和学习小组 LLM 使用模拟响应，不代表生产吞吐量或付费服务的速率限额已验收。

## 导入、清理与导出

- `POST /api/v1/knowledge/{course}/imports` 返回 202 和任务 ID；`GET .../jobs` 查看进度，`POST .../jobs/{id}/retry` 重试。仅课程管理者可操作。
- 默认上传上限 50 MiB、100 页、提取文本 20 万字符、PPTX 解压内容 100 MiB；排队加处理中最多 20 个。重启可恢复未完成任务，失败源文件保留供重试。
- PDF 提取正文和表格，并对扫描页/嵌入图片做 OCR；PPTX 支持分组文本、表格、图表数据、备注和图片文字。复杂公式、图形含义与原始排版不保证还原；识别文字需人工核对。可配置视觉模型进行图片识别。
- 默认保留完成/失败任务 7 天，后台每 3600 秒维护一次，同时清理 SQL 已撤回或被新版本替代的 Chroma 向量。失败任务过期后需要重新上传。
- 旧同步 `/upload` 接口为兼容保留；客户端已用任务接口。文本创建和重建索引仍为同步请求，超大知识库的重建耗时需单独评估。
- 学习小组参与者可通过 `/api/v1/meetings/{room}/minutes/export` 导出 Markdown；客户端调用系统文件保存器。未生成学习总结时返回 409。

## 验证与设备

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

当前 36 项测试通过。手机 API 24 和 MatePad API 24 模拟器使用独立测试数据库；当前 UI 验证实例为 `http://127.0.0.1:8011/docs`，ASR 为 mock，健康检查显示 LLM 已配置，本轮未用该实例提交 AI 请求，不能用它判断真实模型效果。实际服务应按上面的命令读取 `server/.env` 启动。真机填写电脑局域网 IP，并按需允许对应端口通过防火墙。
