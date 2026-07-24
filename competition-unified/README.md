# 智伴单 HAP 比赛版

该目录是独立的比赛提交版本。它把前端页面和 ArkTS 本地后端放进同一个 HAP，HarmonyOS 启动应用时自动初始化后端，无需额外启动 Python、FastAPI 或桌面服务。

## 运行方式

- 入口：`client/entry/src/main/ets/entryability/EntryAbility.ets`
- 本地 API 门面：`client/entry/src/main/ets/service/Api.ets`
- 内嵌后端：`client/entry/src/main/ets/service/LocalBackend.ets`
- 持久化：应用沙箱 `zhiban_local_backend.json`

页面代码与网络版保持同步，只有 `EntryAbility.ets` 和 `Api.ets` 被替换，并增加 `LocalBackend.ets`。比赛版中的题目生成、MAS 回复、知识命中和 ASR 使用离线演示逻辑，不包含 Python、Chroma 或云端模型运行时。

## 构建 HAP

1. 使用 DevEco Studio 6.0+ 打开 `competition-unified/client/`。
2. 等待 Hvigor Sync 完成。
3. 在 `Project Structure > Signing Configs` 中配置当前开发机签名。
4. 选择 `release` 模式并执行 `Build Hap(s)`。

输出目录：

```text
client/entry/build/default/outputs/default/
```

构建缓存、验收截图、解包目录和 HAP 不提交到 Git；正式比赛包建议通过 Release 或 GitHub Releases 单独分发。
