# Muse 原生 Agent 编码验收

任务 ID: T-MUSE-AGENT01
nonce: NONCE-MUSE-AGENT01-20261002

由 Muse runtime 派生的 Agent 自己分析、编写和测试，不启动 Codex 或其他外部 Agent。只在独立工作目录操作，不动 new-api 服务、watchdog、生产环境或历史任务。

## 实际编码任务
为任务总线实现一个独立、无第三方依赖的 Python 模块 task_guard.py，函数 eligible(task, enablement_utc, completed_ids, now_utc) -> bool。
规则：仅 type=agent、target=muse，id 非空且不在 completed_ids；created 必须严格晚于 enablement_utc，且不得晚于 now_utc；如有 expires，now_utc 必须严格早于 expires。时间必须是有效 UTC ISO8601（YYYY-MM-DDTHH:MM:SSZ），无效/缺失关键字段安全拒绝。不要执行任务内容或 shell。
由你自己设计实现与 unittest 测试；至少覆盖可接单、历史、已完成、script、非 muse、过期、未来创建、错误日期、缺字段、到期边界。运行实际测试并保存输出。不要把该模块接入当前调度器，只交付代码供 SG 独立验证。

## 交付
提供 task_guard.py、test_task_guard.py、实际测试日志、manifest.json。manifest 包含 task_id、nonce、执行 host、UTC 开始/结束、任务仓库基线 commit、每个文件 SHA256 与字节数、测试命令与退出码。
本次代码与测试体积很小，可直接通过现有 rentry 回写协议内联交付全部文件（base64url + 独立 SHA256）。使用沙箱已有回写配置及读写帮助代码；读取 /edit 时容错保留已读部分，新 REC 放最前。不得输出 edit_code/凭据，不得把凭据提交到公开库。

## 回库临时路径（明确授权）
已知沙箱 SSH 出网不通且无回执库 PAT。不要反复尝试 SSH，不申请扩大权限。允许使用现有 rentry 回写页作为运输通道，由 Hermes 香港端核验 nonce/文件 SHA256 后写入私有库 1432151545/newapi-receipts，再在 SG 验证。状态写 executed_transport_pending 或 executed，不把“已上传 rentry”等同于“已写 git”；git 入库与 SG 验收由 Hermes 独立确认。
如不能复用现有回写工具，记录具体阻断并向 Muse 主聊天 handoff；不可伪造交付成功。无需用户提供 PAT。
