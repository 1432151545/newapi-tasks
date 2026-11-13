# NewAPI v1.0.0-rc.51 + v68 独立验证任务

- 任务 ID: T-MUSE-V68VERIFY01
- Nonce: NONCE-MUSE-V68VERIFY01-20261113
- 目标接收方: muse1 (htch-runtime agent)
- 生产已切换：`new-api:emptyrefund-rc51-v68`（2026-11-13 23:02 CST）
- 上一版（已验）：rc.50 + v67

## 交付资产

- 下载地址（匿名 GitHub release asset）：
  `https://github.com/1432151545/newapi-artifacts/releases/download/v68-rc51-20261113/new-api-rc51-v68.gz`
- gz SHA256：`f6d47ad08166385910a0399e8ff659798ded265d60b65fed965aa16b006b482b`
- gz 大小：`50601688` 字节
- 解压后二进制 SHA256：`8eac1e9e5a576a1df40b9d5220feda1d6680d0a14f8ee92bbc5bb76e79d9de50`
- 解压后二进制大小：`142864546` 字节
- 版本：`v1.0.0-rc.51`

## 本版变更背景（rc.51 相对 rc.50）

- 上游 rc.50→rc.51 只改依赖与前端：`github.com/MoeForge/moego v0.1.0-alpha.2 → v0.1.0-alpha.3`（修 #8314：无 AVX 的 x86-64 上处理请求时 SIGILL 崩溃）+ 前端密码强度组件；**零 Go 业务源码改动、无表结构迁移**。
- 自研补丁集 v68 = v67 全套（35 文件，含免单 / 订阅掉组 / 订单页 / 邮箱 ATO 根治）重新打到 rc.51 源码，并补回 zh i18n 两条「免单」词条。

## 验证要求

1. 下载 gz，核对 gz SHA256 和大小；解压后核对二进制 SHA256 和大小。
2. 启动独立 SQLite 实例，确认无 FATAL/panic；`--version` 与 `/api/status` 的 `data.version` 均为 `v1.0.0-rc.51`；首页 200；无 token 的 `/v1/models` 为 401。
3. 回传 `go version -m` 或等价的嵌入 Go 版本证据（应为 go1.26.10）。
4. 回传以下补丁 marker 的 `grep -c -a` 实测值：
   - `reapplyEmptyResponseRefund` >= 1
   - `MarkUserSubscriptionsExhausted` >= 1
   - `upstreamHungWithoutFirstByte` >= 1
   - `next_reset_time = 0 AND amount_total > 0` = 2
   - `grep -a -o '免单' <bin> | wc -l` = 3（v68 新增的 zh i18n 词条，用于免单徽标中文显示）
5. 用本地 mock 上游做 relay 全链路：渠道、令牌、`POST /v1/chat/completions`、logs 落账。
6. 重点验证非流式空回复：mock 返回 HTTP 200、`content:""`、usage completion=0；必须看到 `logs.other` 含 `empty_response_refund` 且 `quota=0`。
7. 回归验证正常非流式请求：quota 非零，且没有 refund 标记。
8. 验证 `model_mapping`、流式请求和首字节前断开场景；记录原始证据。
9. SQLite 无法复现 MySQL 的邮箱 collation 折叠时，标记 `not reproducible on SQLite`，不要判负。

## 回传格式

请生成 `report.json`，至少包含：

`task_id`, `nonce`, `gz_sha_match`, `bin_sha_match`, `bin_size_match`, `version_flag`, `api_status_version`, `go_version_embedded`, `patch_markers`, `migration_clean`, `tests_run`, `anomalies`, `overall_result`

## 回执

按现行协议直接 push 到私库 `1432151545/newapi-receipts`：
`receipts/T-MUSE-V68VERIFY01.rec` 和 `receipts/T-MUSE-V68VERIFY01.json`。
不要把任何凭据写入任务或回执。
