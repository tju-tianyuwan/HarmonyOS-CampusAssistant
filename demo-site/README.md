# 智慧伴学产品演示网页 · 产品影像版

独立中文静态展示站，无构建步骤、无第三方 CDN、无需运行产品后端。将整个 `demo-site/` 目录上传到任意静态托管服务即可发布。

2026-09-26 已重新从运行中的 HarmonyOS 平板模拟器采集原生页面，替换上一版全部历史截图与动图。首屏使用新采集的光感学习空间，新增深色影片区、五章节导航、1080p MP4 和新版 GIF。

## 打开

直接用浏览器打开 `index.html`，或在项目根目录运行：

```powershell
python -m http.server 4173 --bind 127.0.0.1 --directory demo-site
```

浏览器访问 `http://127.0.0.1:4173`。

## 内容

- 响应式产品介绍，覆盖课堂转写与审核、课程知识问答、AI 学习小组、笔记、练习、鸿蒙跨端能力。
- 五步交互演示：切换课堂提纲 / 转写、预设 AI 问答、逐角色讨论与总结、可编辑 Markdown 笔记、选择题判题和解析。
- 页面内保存笔记、下载笔记 / 学习总结、重置演示。
- 32 秒、1920×1080、60 fps 的 MP4：设备与镜头全程连续，屏幕在 1.3 秒内交叠过渡，标题和说明错峰淡入，切换时不压暗整台设备。
- 深色播放器支持播放 / 暂停、原生全屏与进度控制、五章节跳转、时间显示和 MP4 / GIF 下载。影片默认不自动播放，离开可见区域时暂停。
- 32 秒循环 GIF 放在可展开的区域，兼顾页面初始加载；普通动效模式下进入视口后播放，减少动态效果模式下手动播放。
- 新采集的学习空间、AI 小组、笔记与实际答题结果可点击放大，支持 Esc 关闭和键盘导航。

交互全部使用明确标注的预设内容，不请求真实 AI、不采集录音、不接触现有账号、后端或数据库。笔记保存在页面内存中，刷新页面会重置；需要保留时可下载 Markdown。

## 文件

| 文件 | 用途 |
| --- | --- |
| `index.html` | 页面结构与产品说明 |
| `styles.css`、`premium.css` | 基础样式及产品影像版视觉 / 响应式布局 |
| `app.js` | 演示、下载、截图查看及动图播放控制 |
| `cinema.js` | 播放器与章节导航 |
| `assets/product-film.mp4` | 32 秒 1080p / 60 fps 产品短片，约 7.4 MB |
| `assets/product-tour.gif` | 32 秒循环动图，854×480 / 20 fps，约 16.3 MB |
| `assets/product-tour-poster.jpg` | 静态封面与减少动态效果替代图 |
| `assets/captures/` | 7 张本次新采集原生画面，保留完整系统栏的 WebP 归档 |
| `assets/captures/provenance.json` | 采集日期、设备、包名、原始 PNG 哈希及处理说明 |
| `film.html`、`film.css`、`film.js` | 可复现的 1920×1080 确定性镜头制作台 |
| `generate_assets.py` | 从本次采集画面裁掉系统栏，生成网站素材 |
| `render_film.py` | 用 Chrome 逐帧渲染，FFmpeg 导出 MP4 和 GIF |
| `check_site.py` | 可选浏览器验收脚本，检查交互、下载和响应式布局 |
| `check_film.py` | 检查转场双层覆盖、镜头连续性与首尾画面一致性 |

重新生成素材需 Pillow；影片还需 Python Playwright、Chrome、中文字体和 FFmpeg。先启动上述预览服务：

```powershell
python demo-site/generate_assets.py
python demo-site/render_film.py
```

仅重建封面与章节静帧可使用 `python demo-site/render_film.py --stills-only`。制作台由 `window.renderFilm(time)` 指定时间，不依赖实时动画计时或外部服务。

## 验证

本次通过 Chrome 无头浏览器验收：1440、1024、768、390、320 像素视口无横向滚动；视频实际解码为 1920×1080，播放、暂停、章节跳转、时间与状态同步通过。课堂切换、预设问答、多角色讨论、笔记会话保存、Markdown 下载、正确 / 错误判题、重置、键盘选项卡、GIF、截图放大和 Esc 关闭均通过。页面无 JavaScript 异常、无资源加载失败，直接打开本地 HTML 的答题流程也通过。

安装了 Python Playwright 且具有 Chrome 的开发环境可在启动预览服务后复验：

```powershell
python demo-site/check_site.py
```

验收截图输出至项目 `.codex-run/demo-site-checks/`，不会加入展示站。

平滑转场版另通过 `python demo-site/check_film.py`：7 个切换点的设备位置无跳变，叠化始终保留不透明底层以避免亮度下陷，片头与片尾画面（进度线除外）像素一致。FFprobe 确认 MP4 为 1920 帧 / 60 fps / 32 秒；GIF 为 640 帧 / 20 fps / 32 秒。

## 内容与素材依据

- 产品能力以根目录 `README.md`、`client/README.md` 及当前 ArkTS 页面为准；未将介绍文档中的规划能力当作已完成特性。
- 课堂角色边界：`client/entry/src/main/ets/pages/RecordPage.ets`、`ClassPage.ets`。
- 学习小组：`client/entry/src/main/ets/pages/MeetingPage.ets` 与 `client/AI_STUDY_GROUP.md`。
- 题目与解析：`client/entry/src/main/ets/pages/PracticePage.ets` 中首道示例题。
- 配色参考：`client/entry/src/main/ets/common/LearningTheme.ets`。
- 品牌图：`assets/branding/app_logo_crystal.png`。
- 所有展示截图来自本次运行中的 `com.demo.smartstudy` 客户端，由 `hdc uitest screenCap` 新采集；不再引用根目录 `演示图/` 下的旧素材。
- 当前采集账号为已有个人测试用户：课程 / 笔记统计为空时保留真实空状态；未伪造课程、AI 回复或讨论记录。多 AI 小组画面展示真实角色介绍。
- 答题画面来自本次实际点击客户端内置二叉树题目并提交的结果；依据 `PracticePage.submitAnswer()`，该流程仅修改当前页面内存状态，不写服务端答题数据。

首屏与截图区保留原生界面像素，仅裁掉系统状态栏与手势区域。MP4 和 GIF 为新采集画面的镜头编排，包含透视、轻微推近、重点框选和触点提示，并非无剪辑的连续录屏。网页五步交互区仍为明确标注的预设流程，不连接真实服务。页面保留云端 ASR、M-Pencil 和隔空传送尚需真实服务 / 真机验收的说明。
