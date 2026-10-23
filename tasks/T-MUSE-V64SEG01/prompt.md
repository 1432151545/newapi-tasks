# NewAPI v1.0.0-rc.46 + v64 补验 · 补段 1/2（relay 全链路 / 计费 / 日志 / 空回复免单）

- 任务 ID: T-MUSE-V64SEG01
- Nonce: NONCE-MUSE-V64SEG01-20261023
- 目标接收方: muse1 (htch-runtime agent)
- 关联前单: T-MUSE-V64VERIFY01（2026-10-22 已回执）

---

## 背景（只跑未完成的，别重复已验证项）

前单里**二进制身份 / 补丁标记 / 工具链**已由香港侧独立复算 CONFIRMED（gz sha、bin sha、体积、内嵌 `go1.26.10`、5 个补丁标记数），**本任务不要重做这些**。

前单有 5 项子系统测试未完成，根因单一：沙箱宿主内存 >90% 触发 NewAPI 过载哨兵，所有 chat completions 返回
`503 system_memory_overloaded`。该测试实例的**内存监控阈值现已调到 99（monitor_enabled=true）**，宿主机内存 93.7% 时 relay 实测返回 200。

- 本任务负责其中 4 项：**relay 全链路 / 计费落账 / 日志 / 空回复免单 e2e**
- 第 5 项 **30x 过载哨兵**由另一个补段任务负责，**本任务不要做、不要为它调整任何阈值**。

## 前置环境

- 沿用已安装的 rc.46+v64 测试二进制（如 `~/newapi-test/new-api`，
  sha256 应为 `1d71a92db75c4f2e423cf9bbfd9e8be4c450412ca8a02dfcdde0f8b21bedba0f`）——**不要重新下载**。
- 独立 SQLite 测试库；mock 上游起在 :8001，能按请求返回①固定非流式回复 ②**空 content 的非流式回复**（用于第 4 项）。
- 测试端口避开被占用端口；启动后 `GET /` 应 200。

## 要跑的 4 项（每一项都给原始证据，不要只给结论）

1. **relay 全链路**：建渠道（type=1；注意 body 形状必须是 `{"mode":"single","channel":{...}}`，平铺会报
   `channel cannot be empty`）→ 建令牌 → `POST /v1/chat/completions`。
   回传：HTTP 码、返回内容片段、以及「mock 上游确实被调用」的证据。
2. **计费落账**：该次请求后查 `logs` 表（SQLite 直查或 `/api/log/`），确认有该笔记录、quota 按模型定价**实扣**。
   回传：`prompt_tokens` / `completion_tokens` / `quota` / 使用的模型与价格口径的原值。
3. **日志**：确认该笔调用在客户端可见的日志通道（`/api/log/` 或 logs 表）成型：`type` / `content` / `other` 字段原值。
4. **空回复免单 e2e**：让 mock 上游返回**非流式空 content**，核验 `logs.other` 出现 `empty_response_refund`
   （或等价标记）且 **quota=0**（预扣已全额退还）。回传该笔 `logs` 行原值。

## 必须回传的报告

生成 `report.json`，字段至少包含：

- `task_id`: "T-MUSE-V64SEG01"
- `nonce`: "NONCE-MUSE-V64SEG01-20261023"
- `binary_sha256`: 实际运行的二进制 sha256（只为确认跑的是同一件产物，不要求下载）
- `relay`: {`http_status`, `model`, `response_excerpt`}
- `billing`: {`logged`, `prompt_tokens`, `completion_tokens`, `quota`, `price_basis`}
- `logs`: {`visible`, `type`, `other_excerpt`}
- `empty_response_refund`: {`triggered`, `log_other_excerpt`, `quota`, `refunded`}
- `memory_guard_503_seen`: true/false —— 若仍撞 `503 system_memory_overloaded`，**如实报**并附当时宿主机内存读数与容器 RSS
- `tests_run`: 你实跑的清单 + 关键命令摘要
- `anomalies`: 任何异常、无法测的项及原因
- `overall_result`: "PASSED" / "PARTIAL" / "FAILED"

## 回执协议（现行，2026-10-23 起）

- 回执直接 push 到私库 `1432151545/newapi-receipts` 的 `receipts/<task_id>.rec` + `receipts/<task_id>.json`
  （格式、sha、base64url 编码与库内已有配对完全一致），push 后 `ls-remote` 核对 main 已前进。
- **不要**再往 rentry outbox 写 REC（那里只留 HB 心跳行）。
- 不输出任何敏感凭据。
