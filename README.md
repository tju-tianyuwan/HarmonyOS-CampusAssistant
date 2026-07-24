# 智慧伴学系统 Demo

面向鸿蒙生态的课堂 AI 协同学习工具。本仓库为 Demo 阶段代码，跑通「录音 → 云端转写 → RAG 提纲/问答 → 班级共享」核心闭环。

- 需求文档：`产品需求文档.md`
- 实现流程：`实现流程.md`

## 目录结构

```
note/
├─ server/        FastAPI 服务端（业务 + AI 层）
├─ client/        HarmonyOS ArkTS 客户端（横屏，6 页面）
├─ 产品需求文档.md
└─ 实现流程.md
```

## 服务端

技术栈：FastAPI + SQLModel(SQLite) + Chroma + OpenAI 兼容 LLM。

```bash
cd server
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt      # Windows；Linux/mac 用 .venv/bin/pip
cp .env.example .env                                # 按需填 LLM_API_KEY（不填走 Mock）
.venv/Scripts/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

> 绑定 `0.0.0.0` 是为了让模拟器/局域网真机能访问；仅本机调试可省略 `--host`。

启动后：
- API 文档：http://127.0.0.1:8000/docs
- 健康检查：http://127.0.0.1:8000/health
- 预置数据：教师「王老师」+学生「小明/小红」，示例集合「计科2301-数据结构」，邀请码 `888888`，1 节已转写课时。

### 关键设计
- **ASR 适配层**（`app/services/asr/`）：`ASRProvider` 抽象接口，默认 `MockASRProvider` 返回预置课堂文本；支持 OpenAI-compatible `/audio/transcriptions` 与华为云 SIS 短语音识别。客户端统一上传 16kHz/单声道/S16LE PCM，每片约 4 秒。

真实 ASR 配置示例：

```env
ASR_PROVIDER=openai
ASR_BASE_URL=https://api.openai.com/v1
ASR_API_KEY=ASR_API_KEY
ASR_MODEL=whisper-1
ASR_LANGUAGE=zh
```

华为云 SIS 配置示例：

```env
ASR_PROVIDER=huawei_sis
SIS_AK=你的访问密钥ID
SIS_SK=你的秘密访问密钥
SIS_PROJECT_ID=区域项目ID
SIS_REGION=cn-north-4
SIS_PROPERTY=chinese_16k_general
SIS_AUDIO_FORMAT=pcm16k16bit
```

`SIS_PROJECT_ID` 必须与 `SIS_REGION` 对应；如果使用控制台热词表，可额外填写 `SIS_VOCABULARY_ID`。
- **LLM**（`app/services/llm.py`）：OpenAI 兼容协议，`base_url/api_key/model` 可配；未配 key 时降级 Mock，保证离线可演示。
- **知识库隔离**（`app/services/rag.py`）：Chroma 按 `class_course_id` 分 collection（`cc_<id>`），检索强制携带集合 ID，跨集合零共享。已验证：向集合 A 发布提纲后，集合 B 问同样问题返回「本课程资料中未找到」。

### API 概览（前缀 `/api/v1`）
| 模块 | 端点 |
|------|------|
| auth | `GET /auth/users` |
| courses | `GET/POST /courses`、`POST /courses/join`、`GET /courses/{id}/stats`（课程工作台真实统计） |
| sessions | 创建课时、`POST /sessions/{id}/chunks/{seq}` 上传分片转写、`POST .../outline/generate` 生成提纲、`POST .../outline/review` 教师审核发布 |
| notes | 笔记 CRUD、`POST /notes/{id}/share` 共享+质量评估入库 |
| chat | 会话管理、`POST /chat/ask` 集合限定 SSE 流式问答 |
| practice | `POST /practice/generate` 基于课程知识库与用户要求生成选择题 |

## 客户端

技术栈：HarmonyOS NEXT + ArkTS/ArkUI（Stage 模型，API 12+）。横屏锁定，**Notein 风格**（#F7F7FA 底、白卡片、墨黑胶囊按钮、#21D5CE 青色点缀）。

结构（仿 Notein 两级形态）：登录 → **课程库**（彩色封面网格 + FAB 创建/加入）→ **课程工作台**（左侧窄图标栏：概览/录音/课时/AI 笔记/笔记/审核(教师)/协同）。

页面：概览（统计+邀请码复制+最近课时）/ 录音（圆形录制钮，AudioCapturer 分片上传实时转写，无麦克风自动降级模拟）/ 课时详情三栏 / AI 笔记（Obsidian 式：SSE 流式问答、划词命令、插入/替换/@引用）/ 刷题（按课程知识库、模式、知识点、难度和自由要求调用 AI 生成选择题，并提供答题判定与解析）/ 笔记（MD + 手写悬浮笔盒：5 色 3 档笔宽压感预留）/ 教师审核 / **协同**（NFC 碰一碰写卡入班、局域网 UDP 发现 + TCP 互抓笔记、跨端接续快照，均需真机）。

**联调地址**：`client/.../service/Api.ets` 的 `BASE_URL` 默认 `http://10.0.2.2:8000/api/v1`（模拟器经 QEMU NAT 访问宿主机回环）。若不通改为电脑局域网 IP；真机联调必须用局域网 IP 且服务端 `--host 0.0.0.0`。

## 测试

### 服务端一键冒烟测试
```bash
cd server
.venv/Scripts/python -m uvicorn app.main:app --port 8000   # 终端1：启动服务
.venv/Scripts/python smoke_test.py                          # 终端2：跑测试
```
`smoke_test.py` 覆盖健康检查、课程创建与加入、录音转写、提纲发布、集合限定问答、知识库 AI 选择题生成、跨集合隔离、笔记共享质量评估和课程统计。全部 PASS 即服务端正常。

### 手动调试
浏览器打开 http://127.0.0.1:8000/docs（Swagger UI），可逐个接口点 "Try it out" 调试；SSE 问答接口建议用 curl：`curl -N -X POST .../api/v1/chat/ask -H "Content-Type: application/json" -d @body.json`。

### 重置演示数据
删除 `server/smartstudy.db` 和 `server/data/` 后重启服务，将重新生成预置数据（两者必须一起删，保持业务库与向量库一致）。

## 已验证的闭环
录音分片上传→Mock 转写落库→生成 Markdown 提纲→教师发布入知识库→集合限定问答（带引用来源、流式）→跨集合隔离→笔记共享质量评估入库，均已通过接口冒烟测试。

## 待办（Demo 后）
- 按实际课堂环境调优 SIS 模型与热词表
- 真机验证：手写压感（MatePad + M-Pencil）、NFC 碰一碰（NDEF 标签）、局域网互抓（两台真机同 WLAN）、跨端接续（同华为账号）
- UI 动画、Markdown 富渲染、PDF 导出

> 夜间自主迭代的详细改动与测试指引见《交接说明.md》。
