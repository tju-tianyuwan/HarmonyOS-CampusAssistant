# collab 协同层

本目录通过现有 CollabManager 管理：

- NfcService：NFC 标签读取、课程邀请码和学习状态。
- EntryAbility：系统应用接续，目标端重新校验登录账号和课程成员资格。
- TransferService：Share Kit 的 gesturesShare 与 dataReceive，接入系统握拳抓取、张手释放。传送当前笔记或学习状态，默认开启；笔记保存至接收端当前课程。

要求支持 HarmonyShare 的 API 20+ 设备。不支持时记录能力不可用，不注册手势回调。没有自建 UDP/TCP 协议，也不会在设备间传递登录 token。系统手势识别及设备发现由鸿蒙负责，需要真机验证。
