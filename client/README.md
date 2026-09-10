# 智慧伴学 HarmonyOS 客户端

`client/` 是连接 FastAPI 服务端的网络版 HarmonyOS 客户端，使用 ArkTS/ArkUI Stage 模型，支持 API 12+ 的 Tablet、2in1 和 Phone。平板保持横屏，手机启用自动旋转并提供竖屏紧凑布局。

## 页面

- 登录与课程库：邮箱/学校账号注册登录，个人知识空间，创建或通过邀请码加入课程。
- 账号安全：邮箱验证码找回密码、验证当前密码后修改密码、学校账号绑定找回邮箱；改密后所有设备需重新登录。
- 概览：课程信息、官方课时、个人笔记、班级笔记和快捷入口。
- 课堂：录音、分片上传、实时转写、提纲生成与教师发布。
- AI：课程知识库问答和 MAS 多智能体讨论。
- 刷题：根据课程知识库与用户要求生成选择题。
- 笔记：班级笔记、Markdown/AI 笔记和矢量手写笔记；手写本机草稿、离开提示、恢复与跨屏缩放。触控笔压力映射线宽并随笔迹保存，M-Pencil 效果待真机验证。
- 知识库：后台上传 PDF/PPTX/文本、任务进度及失败重试、检索、重建索引和模型连接测试。
- 聊天室：课程会议、成员消息、智能体开关、纪要、Markdown 导出和结束会议，以及成员添加、移除、重新邀请、退出和主持权转交。
- 设置：服务器地址、NFC、系统隔空传送和跨端接续。握拳抓取/张手释放需要支持该功能的 API 20+ 华为真机。

## 打开与运行

1. 安装 DevEco Studio 6.0+ 和 HarmonyOS SDK API 12+。
2. 打开本 `client/` 目录并等待 Hvigor Sync。
3. 在 `Project Structure > Signing Configs` 中为本机生成签名。
4. 启动后端，再运行 `entry` 模块。

模拟器访问宿主机使用：

```text
http://10.0.2.2:8000/api/v1
```

真机联调时，在应用设置页改为电脑局域网地址，并确保后端通过 `--host 0.0.0.0` 启动。

## 源码结构

```text
client/
├─ AppScope/                       应用配置与图标
├─ build-profile.json5             SDK、产品和模块配置
├─ hvigor/                         Hvigor 配置
└─ entry/src/main/
   ├─ module.json5                 Ability、权限和横屏配置
   ├─ ets/
   │  ├─ entryability/             应用入口与跨端恢复
   │  ├─ common/                   主题与通用组件
   │  ├─ model/                    前后端数据模型
   │  ├─ pages/                    课程、AI、刷题、笔记等页面
   │  └─ service/
   │     ├─ Api.ets                HTTP、上传和 SSE 封装
   │     ├─ GlobalState.ets        用户、课程与接续状态
   │     └─ collab/                NFC 与局域网协同
   └─ resources/                   字符串、颜色、图标和页面清单
```

## 构建

DevEco Studio 中选择 `entry` 模块后执行 `Build Hap(s)`。签名材料是开发机私有配置，不保存在仓库中；首次构建必须在 IDE 中重新配置签名。

生成的 `.hvigor/`、`oh_modules/`、`entry/build/` 和 HAP 文件均已加入 `.gitignore`。
