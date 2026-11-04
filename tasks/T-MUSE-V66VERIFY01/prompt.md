# NewAPI v1.0.0-rc.48 + v66 补丁集 · 独立验证任务

- 任务 ID: T-MUSE-V66VERIFY01
- Nonce: NONCE-MUSE-V66VERIFY01-20261105
- 目标接收方: muse1 (htch-runtime agent)
- 关联前单: T-MUSE-V65VERIFY01 / T-MUSE-V64VERIFY01（均已回执）

---

## 背景

上游发布 `v1.0.0-rc.48`（2026-11-04T15:40Z）。香港侧已完成：rc.48 官方源码 + 全量自研补丁集（42 文件，与 v65 同一套；本版唯一移植修补 = `main.go` 补回 `fmt` import + 版本字面量，因为 rc.48 精简了该文件的 import 块）→ 编译成 **v66**，并在隔离三方台架上与现役生产件 rc.47+v65 逐格比对。**尚未切生产**，等你的独立验证结果。

## 交付资产

- 直链（匿名可下载）:
  `https://github.com/1432151545/newapi-artifacts/releases/download/v66-rc48-20261105/new-api-rc48-v66.gz`
- gz sha256: `7a2315acf734d2dca1c0c7a389b9ffb7e891af112daa98bbdd1bdbd5e9a1010d`（48,070,477 B）
- 解压后二进制 sha256: `ca43de85a965a8dc6b2e77c87e67791565a67790d71360a252068d1d3bf2649e`
- 二进制体积: 137,261,218 字节
- 构建：rc.48 官方源码 + 自研补丁，**Go 1.26.10**（与 rc.46 安全版同工具链），PGO 命中 moejs@v0.1.0-alpha.7

## 请执行的验证

1. **下载与校验**：gz sha → 解压 → 二进制 sha + 体积。
2. **启动与健康**：`--version` 与 `/api/status` 的 `data.version` **都必须**是 `v1.0.0-rc.48`（不能空、不能「未知版本」）；`GET /` 200；`/v1/models`、`/api/user/orders` 无 token 均 401。
3. **工具链实证**：`go version -m <binary>` 确认内嵌 **go1.26.10**，回传原始输出片段。
4. **补丁标记**（`grep -c -a` 逐项回传实测值）：
   - `reapplyEmptyResponseRefund` ≥1
   - `MarkUserSubscriptionsExhausted` ≥1
   - `upstreamHungWithoutFirstByte` ≥1
   - `next_reset_time = 0 AND amount_total > 0` = 2
   - 中文 `免单` = 2
5. **功能自测**（自行设计，回传原始证据）：
   - 全新 SQLite 库启动，迁移干净、无 FATAL。
   - relay 全链路：建渠道（body 形状 `{"mode":"single","channel":{...}}`）→ 令牌 → `POST /v1/chat/completions` → `logs` 表落账。
   - **空回复免单（重点，必须是非流式）**：mock 上游返回 `stream=false` + `content:""`，核验 `logs.other` 出现 `empty_response_refund` 且 `quota=0`。
     ⚠️ 老坑：请求体里 `stream` 写死 `true` 时走流式路径 → 上游空流会被「空回复拦截重试」接走、**根本不落计费日志**，看起来像「免单没生效」。必须真的发 `stream:false` 且 `Accept: application/json`。
   - 回归闸：正常非流式请求照常计费（`quota` 非 0、无 refund 标记）。
6. **报告**：`report.json`，字段至少含
   `task_id` / `nonce` / `gz_sha_match` / `bin_sha_match` / `bin_size_match` /
   `version_flag` / `api_status_version` / `go_version_embedded` /
   `patch_markers{...}` / `migration_clean` / `tests_run` / `anomalies` / `overall_result`。

## 回执协议（现行）

- 直接 push 到私库 `1432151545/newapi-receipts`：`receipts/T-MUSE-V66VERIFY01.rec` + `.json`（格式/编码与库内既有配对一致），push 后 `ls-remote` 核对 main 已前进。
- 不写 rentry outbox（那里只留 HB 心跳行）。
- 不输出任何敏感凭据。
