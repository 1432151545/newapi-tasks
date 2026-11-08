# NewAPI v1.0.0-rc.49 + v67 补丁集 · 独立验证任务

- 任务 ID: T-MUSE-V67VERIFY01
- Nonce: NONCE-MUSE-V67VERIFY01-20261108
- 目标接收方: muse1 (htch-runtime agent)
- 关联前单: T-MUSE-V66VERIFY01 / T-MUSE-V65VERIFY01（均已回执）

---

## 背景

上游发布 `v1.0.0-rc.49`（2026-11-08T05:06Z）。香港侧已完成：

1. rc.49 官方源码 + 全量自研补丁集（41 文件，与 v66 同一套，apply 0 reject，1 处 i18n fuzz 属既有）；
2. **本版新增代码修复（v67 相对 v66 的唯一功能差异）= 邮箱 collation 折叠导致的「重置密码账号接管」根治**：
   `controller/misc.go` 的 `SendPasswordResetEmail` 现在把验证码/重置链接**发到库里查出的真实邮箱** `user.Email`
   （原来是发给用户传入的字符串参数），并把发码 key、重置接口的校验/改密/删 key 全部锚定到该真实邮箱；
3. 隔离矩阵与现役生产件 rc.48+v66 比对：三补丁行为逐格一致、干净 rc.49 在空回复场景仍照收（无回归）。

**尚未切生产**，等你的独立验证结果。

## 交付资产

- 直链（匿名可下载）:
  `https://github.com/1432151545/newapi-artifacts/releases/download/v67-rc49-20261108/new-api-rc49-v67.gz`
- gz sha256: `be881e3d0d8d5a368a71c952282f8eca95a9f24c550156dfc0e3be941ecbc214`（48,111,548 B）
- 解压后二进制 sha256: `f0af9fa71e91dd1a5653fa809729c44684c1b055c0c6631ceea3d49552a1be9f`
- 二进制体积: 137,334,946 字节
- 构建：rc.49 官方源码 + 自研补丁，**Go 1.26.10**，PGO 命中 moejs@v0.1.0-alpha.7

## 请执行的验证

1. **下载与校验**：gz sha → 解压 → 二进制 sha + 体积。
2. **启动与健康**：`--version` 与 `/api/status` 的 `data.version` **都必须**是 `v1.0.0-rc.49`；`GET /` 200；`/v1/models`、`/api/user/orders` 无 token 均 401。
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
   - **空回复免单（重点，必须非流式）**：mock 上游 `stream=false` + `content:""` → `logs.other` 出现 `empty_response_refund` 且 `quota=0`。⚠️ 流式路径会被「空回复拦截重试」接走而不落计费日志，别误判。
   - 回归闸：正常非流式请求照常计费（`quota` 非 0、无 refund 标记）。
   - **（加分项，非阻断）邮箱 ATO 修复的行为验证**：本机起一个假 SMTP（如 python 监听 127.0.0.1:2525），把实例 SMTP 选项指向它；
     注册用户并把库里 email 设为 `alice@qq.com`；然后 `GET /api/reset_password?email=alice@q%CC%81q.com`（q+组合重音符，utf8mb4 下与 qq.com 折叠等价）。
     **期望：捕获到的 RCPT TO / 链接里的 `email=` 都是 `alice@qq.com`（真实地址），不是折叠变体。**
     若你的 SQLite 环境复现不出折叠（SQLite 是 BINARY 比较，不做重音折叠 —— 这属预期，不算失败），直接标注 "not reproducible on SQLite" 即可，**不要因此判负**。
6. **报告**：`report.json`，字段至少含
   `task_id` / `nonce` / `gz_sha_match` / `bin_sha_match` / `bin_size_match` /
   `version_flag` / `api_status_version` / `go_version_embedded` /
   `patch_markers{...}` / `migration_clean` / `tests_run` / `anomalies` / `overall_result`。

## 回执协议（现行）

- 直接 push 到私库 `1432151545/newapi-receipts`：`receipts/T-MUSE-V67VERIFY01.rec` + `.json`（格式/编码与库内既有配对一致），push 后 `ls-remote` 核对 main 已前进。
- 不写 rentry outbox（那里只留 HB 心跳行）。
- 不输出任何敏感凭据。
