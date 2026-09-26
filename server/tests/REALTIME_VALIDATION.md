# 华为云实时识别验收记录（2026-09-26）

## 已验证

- 服务端完整回归：65 项通过。
- 客户端录音生命周期：18 项通过，覆盖 60 秒切分、缓存写失败保留、暂停封口、丢失确认后去重。
- ArkTS 构建：`entry@default` 和 `entry@ohosTest` 的 `assembleHap` 成功。HAP 已覆盖安装到原有 MatePad Pro 13、HarmonyOS API 24 模拟器，未清除应用数据。
- 设备集成测试：实际 ArkTS WebSocket 和实际设备文件存储，云端使用明确标记的模拟 SIS。4 组通过：PCM 追加和偏移读取、草稿恢复；END 前中间结果及断线缓存保留；重放、最终确认和去重清理；暂停恢复后的累计时间戳及课时完成。退出码 0。
- 真实 SIS：用户更新凭据后，连续模式 START/END 握手成功。以 200ms 帧发送项目现有 7.85 秒中文测试音频，收到 17 次中间结果和 1 次最终结果，无待确认中间结果。原始识别：“今天我们学习二叉数前序，便利的顺序是根结点，左子数，右子数。”
- 后端 8000 端口：健康检查返回 `ok=true`、`asr_provider=huawei_sis_realtime`、`asr_configured=true`。

## 设备测试复现

从 server 目录运行 `.venv/Scripts/python.exe -m tests.realtime_device_server`。测试服务只监听本机 8012，创建临时数据库，不使用真实云端凭据，不修改 `smartstudy.db`。模拟器通过 `10.0.2.2:8012` 访问。构建并安装 default 和 ohosTest HAP 后执行：

```text
hdc -t 127.0.0.1:5555 shell aa test -b com.demo.smartstudy -m entry_test -s unittest OpenHarmonyTestRunner -w 120000
```

测试代码只在 ohosTest 包中，正式客户端不包含测试 token 或测试服务切换入口。

## 尚未证明

设备自动化验证覆盖网络和缓存，不等于麦克风录制到真实云端的完整课堂验收。桌面自动化辅助进程本次无法启动，未完成录音页面操作路径的视觉验收。专业词存在同音误识别；真实课堂噪声准确率、实际字幕延迟、连续 45 分钟稳定性、60 秒重连边界的词句完整性需进一步实录测试。当前不自动回退到本地或模拟 ASR。
