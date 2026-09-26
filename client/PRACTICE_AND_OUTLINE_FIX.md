# 刷题课程隔离与提纲公式渲染

## 行为变更

- 刷题页移除硬编码的二叉树、图、排序知识点及示例题库。
- `GET /api/v1/practice/context` 从当前课程的可检索知识文档提取知识点和实际资料来源，不调用 LLM。
- 从课堂详情切换刷题时，携带 `session_id`；从课程首页进入时使用整门课程。返回首页或更换课程会清除过期课次上下文。
- 进入页签先显示当前课程信息，点击“生成本课练习”或“AI 出题”才请求生成；无资料、加载失败时明确提示，不用示例题补位。
- 切换课程、退出页面后到达的旧请求不会写入当前题组。知识点右侧显示来源资料数量，不再显示示例题数量。
- 提纲浏览改用离线 Markdown + LaTeX 渲染。课堂详情、课程提纲、录音后提纲、教师审核页共用同一渲染组件。编辑仍保留源码与预览切换。
- 支持 `$…$`、`$$…$$`、`\(…\)`、`\[…\]` 及常见公式环境。不支持或格式错误的公式保留原文，避免整页空白。

## 实现位置

- `entry/src/main/ets/pages/PracticePage.ets`
- `../server/app/routers/practice.py`
- `../server/app/services/practice_context.py`
- `entry/src/main/ets/common/components/MarkdownView.ets`
- `entry/src/main/resources/rawfile/math/`：固定版本的 KaTeX、Marked、DOMPurify 与许可证、资源校验清单。

数学表达式在 Markdown 解析前识别，避免反斜杠、下标和矩阵换行被误处理。渲染页不开放网络请求或外部图片，不执行原文 HTML；没有把课程内容发送给外部渲染服务。

## 验证记录（2026-09-26）

- 鸿蒙客户端 `assembleHap` 编译成功，产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`。
- 刷题后端 7 项测试通过（含课程/课次隔离、未发布提纲、无资料课程、权限校验）。
- 新增前端课程状态 7 项、数学解析 3 项测试通过；其余现有前端测试通过。
- 后端安全工作流 37 项测试在项目隔离临时目录下通过。首次受限运行因 Windows 文件权限失败，放开对应测试进程后重跑通过。
- 实际浏览器截图 `.codex-run/math-check/formula-render-final.png`：5 个公式、0 个渲染错误、无外部图片/框架，代码片段保持原样。

## 安装、设备验证与远程部署状态

- 先前覆盖安装因 `install sign info inconsistent` 失败。随后检查当前平板模拟器，发现主应用尚未安装，已成功安装最新 HAP 并启动至登录页；本次没有卸载原应用或更改签名。
- 在同一平板模拟器安装独立验证程序，使用生产代码原样复制的 `MarkdownView` 和离线资源，已确认标题、行内公式、独立公式、积分、矩阵正常渲染；360 vp 与平板宽度均已截图检查。截图：`.codex-run/outline-arkweb.png`、`.codex-run/outline-arkweb-narrow.png`。这是组件设备验证，尚不代表远程真实课堂已完成端到端验收。
- 用户实际服务为 `http://zhiban.help:8000`。原 OpenAPI 没有 `/api/v1/practice/context`，出题请求也没有 `session_id`，这是仅更新本地后端仍无效的原因。
- 经用户授权 SSH 登录，确认部署位置 `/opt/campus/server`，运行服务 `campus.service`，原启动命令为虚拟环境 Python 运行 `run.py --host 127.0.0.1 --port 8001 --workers 1`，外部 8000 由既有代理提供。
- 已核对远程数据模型、知识库检索、权限及出题模块兼容性，在远程原虚拟环境中验证新增模块可正常加载，备份原路由至 `/opt/campus/server/backups/practice-20260926-1625/original-practice.py`。仅替换 `app/routers/practice.py` 并新增 `app/services/practice_context.py`，之后重启原服务；没有新增依赖、修改配置或主动迁移数据库。
- 重启后公开健康检查正常，OpenAPI 已包含 context 接口和 session_id。已在只读数据库会话中核对实际课程 6 / 课次 3（“数据结构”内的“9月26日课堂”），知识点为映射与值域、二次函数、定义域与值域等，出题材料仅为该课次提纲。课程名称“数据结构”是数据库真实名称，并非前端写死。
- 使用该课程实际学生的权限上下文验证知识点与跨课程课次拒绝逻辑，通过。在只读数据库会话中调用一次真实模型生成（1 题），题目为“将函数 f(x)=x² 看作从实数集到实数集的映射时，下列说法正确的是”，来源仅“提纲：9月26日课堂”；没有提交答案或写入学生作答记录。
- 排查时启动的本地临时后端已结束；远程生产服务保持运行。
- 平板主应用已保存远程服务地址。等待学生正常登录后，继续真实页面端到端验收。物理设备未操作。主机验证记录仅保存在项目 `.codex-run/zhiban-known-hosts`；登录凭据未保存到项目文件。
