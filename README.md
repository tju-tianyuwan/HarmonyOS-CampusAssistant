# 智慧伴学（智伴）

面向 HarmonyOS 的课堂 AI 协同学习 Demo，覆盖课程工作台、课堂录音转写、课程提纲、个人与班级笔记、MAS 多智能体讨论和 AI 选择题练习。

![课程概览](演示图/frontend-overview.jpeg)

## 功能概览

- **课程工作台**：按课程显示官方课时、个人笔记和班级笔记统计，每 3 秒同步一次服务端快照。
- **课堂记录**：采集 16 kHz 单声道 PCM 音频，分片上传 ASR，并基于转写生成 Markdown 提纲。
- **课程知识库**：发布的官方提纲和通过质量评估的共享笔记进入 Chroma，按课程 collection 隔离。
- **AI 与 MAS**：支持单助手问答，以及分析、质疑、类比、总结等不同性格智能体参与的课堂讨论。
- **笔记工作台**：支持 Markdown/AI 笔记、矢量手写笔记、个人管理、班级共享和再次编辑。
- **刷题**：根据课程知识库、知识点、难度和用户要求生成选择题，提供判题与解析。
- **HarmonyOS 协同**：包含 NFC 标签接续、局域网发现与笔记互抓、跨端状态接续的 Demo 实现。

## 两种运行模式

| 目录 | 用途 | 后端 |
| --- | --- | --- |
| `client/` + `server/` | 日常开发和实际前后端联调 | FastAPI + SQLite + Chroma + 可配置 LLM/ASR |
| `competition-unified/` | 比赛单 HAP 演示 | HAP 内嵌 ArkTS 本地后端，无需 Python 服务 |

统一比赛版保持与网络版相同的页面 API，但 AI、ASR 和知识检索采用离线演示逻辑，不包含 Python、Chroma 或第三方模型运行时。实际部署应使用 `client/` 与 `server/` 的前后端分离结构。

## 项目结构

```text
HarmonyOS-CampusAssistant/
├─ client/                 HarmonyOS ArkTS 网络版客户端
├─ server/                 FastAPI 业务、AI、ASR 与 RAG 服务
├─ competition-unified/    单 HAP 比赛版源码
├─ image/README/           README 图片资源
├─ 演示图/                  功能演示截图
├─ 产品需求文档.md
└─ 实现流程.md
```

## 启动网络后端

要求 Python 3.11+。PowerShell 示例：

```powershell
cd server
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

启动后可访问：

- 健康检查：`http://127.0.0.1:8000/health`
- Swagger API：`http://127.0.0.1:8000/docs`
- API 前缀：`http://127.0.0.1:8000/api/v1`

`.env.example` 包含 DeepSeek/OpenAI 兼容 LLM、OpenAI 兼容 ASR、华为云 SIS、Embedding、数据库和存储目录配置。未配置 LLM 或 ASR 密钥时使用 Demo 降级实现。

## 运行网络版客户端

1. 使用 DevEco Studio 6.0+ 打开 `client/`。
2. 等待 Hvigor Sync 完成。
3. 在 `Project Structure > Signing Configs` 中为本机生成调试或发布签名。
4. 启动 API 12+ 的 Tablet、2in1 或 Phone 设备，运行 `entry` 模块。
5. 模拟器默认通过 `http://10.0.2.2:8000/api/v1` 访问宿主机；真机请在应用设置页填写电脑局域网地址。

签名证书、密码、HAP、`oh_modules` 和构建缓存均不进入 Git 仓库。

## 构建单 HAP 比赛版

1. 使用 DevEco Studio 打开 `competition-unified/client/`。
2. 完成 Hvigor Sync，并为当前开发机配置签名。
3. 选择 `entry` 模块和 `release` 构建模式。
4. 执行 `Build > Build Hap(s)/APP(s) > Build Hap(s)`。

默认输出目录：

```text
competition-unified/client/entry/build/default/outputs/default/
```

应用启动时由 `EntryAbility.onCreate()` 初始化内嵌后端，数据保存在 HarmonyOS 应用沙箱的 `zhiban_local_backend.json` 中。无需启动桌面端服务。

## 数据隔离

网络版当前使用一个业务数据库，通过 `class_course_id` 对课程、课时、笔记、会话和统计进行逻辑隔离；Chroma 使用 `cc_<class_course_id>` 独立 collection。比赛版使用一个应用沙箱 JSON 文件，并在每条记录上保存课程 ID。

如需重置网络版 Demo 数据，停止服务后删除 `server/smartstudy.db` 和 `server/data/`，再次启动会恢复种子数据。

## 测试

安装服务端依赖后运行：

```powershell
cd server
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

完整接口冒烟测试需要先启动后端：

```powershell
.\.venv\Scripts\python.exe smoke_test.py
```

当前单元测试覆盖课程统计隔离、MAS 角色编排和刷题 JSON 校验；`smoke_test.py` 覆盖课程、录音、提纲、问答、刷题、共享笔记和统计闭环。

## Demo 说明

当前账号页使用预置用户直接选择身份，适合比赛演示和本地联调。面向真实用户部署前，需要补充正式登录认证、接口级所有权校验、局域网传输认证/加密、数据库迁移与发布签名流程。
