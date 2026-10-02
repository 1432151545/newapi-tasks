# T-GITAGT01 — agent 通道端到端验证

请在被认领后按下列最小步骤执行，并把结果按既有 outbox REC 契约回报（`agent-outbox-report.py` 或等价物）：

1. 打印当前主机名与 UTC 时间；
2. 打印你是从哪个目录/文件被触发的（例如 `~/.hermes-gitbus/agent_inbox/T-GITAGT01.md`）；
3. 报告你的执行器名称与版本（例如你所用 CLI/模型的标识）；
4. 输出一行：`AGENT-CHANNEL-OK`。

要求：回报必须是可核验的 REC（含 nonce `NONCE-GIT-AGT-300` 与 exit 码），内容放 result JSON，
不要只写聊天消息。