# 智慧伴学 · HarmonyOS NEXT 客户端（Demo 骨架）

横屏鸿蒙应用 Demo（Stage 模型，API 12+，ArkTS/ArkUI），对应《产品需求文档》M1 阶段：横屏框架 + 全部 6 个静态页面（mock 数据）。

- Bundle Name：`com.demo.smartstudy`
- 应用名：智慧伴学

## 用 DevEco Studio 打开

1. 安装 DevEco Studio 5.0 及以上（含 HarmonyOS NEXT SDK，API 12+）。
2. `File → Open`，选择本 `client` 目录（工程根，含 `build-profile.json5`）。
3. 首次打开等待 hvigor Sync 完成（会自动下载 `@ohos/hvigor-ohos-plugin` 等依赖）。
4. `File → Project Structure → Signing Configs`，勾选 **Automatically generate signature** 完成自动签名（模拟器/真机运行均需要）。

## 模拟器横屏运行

1. `Tools → Device Manager` 创建/启动模拟器（建议 **Tablet** 或 2in1 设备镜像，横屏演示效果最佳）。
2. 选择 `entry` 模块，点击 Run。
3. 应用在 `module.json5` 中已设置 `"orientation": "landscape"`，启动后自动锁定横屏；若模拟器仍竖屏显示，用模拟器工具栏的旋转按钮转为横向即可。

## 目录结构

```
client/
├─ AppScope/                     应用级配置（bundleName、图标、应用名）
├─ build-profile.json5           工程级构建配置（SDK 版本、模块列表）
├─ hvigorfile.ts / hvigor/       构建脚本与 hvigor 配置
├─ oh-package.json5              工程级依赖
└─ entry/                        主模块（entry HAP）
   ├─ build-profile.json5 / hvigorfile.ts / oh-package.json5
   └─ src/main/
      ├─ module.json5            EntryAbility、横屏锁定、INTERNET 权限
      ├─ ets/
      │  ├─ entryability/EntryAbility.ets
      │  ├─ pages/
      │  │  ├─ Index.ets              唯一 @Entry：Navigation + NavPathStack 路由容器
      │  │  ├─ HomePage.ets           P1 集合列表（首页，Navigation 首内容）
      │  │  ├─ RecordPage.ets         P2 课堂录音（UI 状态机，录音待接入）
      │  │  ├─ SessionDetailPage.ets  P3 课时详情（三栏）
      │  │  ├─ AiNotePage.ets         P4 AI 问答（Obsidian 式编辑器 + AI 侧栏）
      │  │  ├─ NotesPage.ets          P5 笔记（MD/手写两类）
      │  │  └─ ReviewPage.ets         P6 教师审核
      │  ├─ common/
      │  │  ├─ AppTheme.ets           主题常量（主色 #2E7DFF、灰阶、圆角 12vp、间距）
      │  │  └─ components/
      │  │     ├─ TwoPane.ets         双栏容器（左 280vp 固定 + 右自适应）
      │  │     └─ AppCard.ets         卡片组件（样式参数化，预留动画挂载点）
      │  ├─ model/Models.ets          数据模型 interface + mock 数据
      │  └─ service/
      │     ├─ Api.ets                网络层封装占位（baseUrl + http get/post）
      │     └─ collab/README.md       协同层（NFC/流转）占位
      └─ resources/base/
         ├─ element/string.json / color.json
         ├─ media/app_icon.png        占位图标（见下）
         └─ profile/main_pages.json
```

## 路由说明

页面全部注册在 `Index.ets` 的 `Navigation.navDestination` 中，路由名：
`record` / `sessionDetail` / `aiNote` / `notes` / `review`。首页 HomePage 直接作为 Navigation 内容区。跳转统一走 `NavPathStack.pushPathByName(name, param)`，后续可在此容器上统一挂转场动画。

## 需要手动处理的事项

- **应用图标**：`AppScope/resources/base/media/app_icon.png` 与 `entry/.../media/app_icon.png` 目前是 1x1 像素占位图。请在 DevEco Studio 中右键 `media` 目录 → `New → Image Asset`（或替换为正式 PNG / layered_image 结构）生成正式图标。
- **签名**：首次运行前完成自动签名（见上文）。
- `service/Api.ets` 的 `BASE_URL` 指向本地 FastAPI（`http://127.0.0.1:8000/api/v1`），联调时按实际服务端地址修改；当前页面均使用 mock 数据，不发起真实请求。
