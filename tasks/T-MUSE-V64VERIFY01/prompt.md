# NewAPI 生产更新自测验证任务 (v1.0.0-rc.46 + v64 补丁集)

- 任务 ID: T-MUSE-V64VERIFY01
- Nonce: NONCE-MUSE-V64VERIFY01-20261022
- 目标接收方: muse1 (htch-runtime agent)
- 关联变更: 上游发布 v1.0.0-rc.46（安全版本，Go 1.26.10 修 CVE-2026-111943），生产已在香港完成热切换（rc.45+v63 → rc.46+v64）。现交付给你自行完整测试验证。

---

## 交付资产信息
- 交付文件（单文件直链，匿名可下载）:
  `https://github.com/1432151545/newapi-artifacts/releases/download/v64-rc46-20261022/new-api-rc46-v64.gz`
- 压缩包 sha256: `8ee18da443957d4b8053af8fff4310ed45b4d76903a3d751b33049e5b629435f`
- 解压后二进制 sha256: `1d71a92db75c4f2e423cf9bbfd9e8be4c450412ca8a02dfcdde0f8b21bedba0f`
- 二进制体积: 136626338 字节
- 构建方式: 官方 rc.46 源码 + 自研补丁，用 **Go 1.26.10** 编译（这是本版安全的实质，请重点核验）

---

## 你需要执行的测试与验证（请自主测试）

1. **下载与校验**
   - 从上述 GitHub release 直链下载 `new-api-rc46-v64.gz`。
   - 校验 gz sha256 → 解压得到 `new-api` → 校验二进制 sha256 与体积。
   - 安装替换到测试路径（如 `~/newapi-test/new-api`），`chmod +x`。

2. **启动与健康检查**
   - 启动本地服务（测试端口，注意端口占用）。
   - `GET /` 应 200；`--version` 应输出 `v1.0.0-rc.46`。
   - `GET /api/status` 的 `data.version` **必须**为 `"v1.0.0-rc.46"`（不能是空串/「未知版本」）。
   - `GET /v1/models` 与 `GET /api/user/orders` 无 token 均应 401。

3. **编译工具链实证（本版新增重点）**
   - 用 `go version -m <binary>`（若沙箱有 go；没有则用 `strings`/`grep -a` 佐证）确认二进制内嵌的 **Go 版本为 go1.26.10**，而非 1.26.1/1.27.1 —— 这是 CVE-2026-111943 修复是否真正落进产物的唯一硬证据。
   - 回传你用的命令与原始输出片段。

4. **自研补丁集存在性核验（二进制内字符串）**
   - `grep -c -a` 分别统计并回传：
     - `reapplyEmptyResponseRefund`（空回复免单，二次归零）
     - `MarkUserSubscriptionsExhausted`（订阅额度用尽掉组，事件驱动）
     - `upstreamHungWithoutFirstByte`（上游首字节从未到达 + 挂满 60s 的免单判据）
     - 字面量 `next_reset_time = 0 AND amount_total > 0`（掉组 SQL 判据）
     - 中文串 `免单`（前端徽章文本，预期 2）
   - 预期：前三项各 ≥1，SQL 判据 2，`免单` 2。逐项给出实测值。

5. **自主功能测试（请自行设计并执行）**
   - 数据库初始化/迁移：本版新增 `quota_data.cache_read_tokens`、`cache_creation_tokens` 两列与 `audit_logs` 的一个联合索引，请确认全新库启动迁移干净、无 FATAL。
   - 全链路 relay：建渠道（mock 上游）→ 建令牌 → chat/completions → 查 `logs` 表计费落账。
   - 空回复免单：让 mock 上游返回**非流式**空回复，核验 `logs.other` 中是否出现 `empty_response_refund`，且 `quota=0`。
   - 高负载/过载哨兵：短时并发打一轮，确认不因误判过载返回 503。
   - rc.46 上游变更抽验（能测就测，测不了要说明）：Resend 邮件配置项、任务换渠道重试按新价预扣、DeepSeek 美元余额为 0 时回退人民币显示。

6. **生成测试报告与回传**
   - 整理 `report.json`，字段至少包含：
     - `task_id`: "T-MUSE-V64VERIFY01"
     - `nonce`: "NONCE-MUSE-V64VERIFY01-20261022"
     - `gz_sha_match` / `bin_sha_match` / `bin_size_match`: true/false
     - `version_flag` / `api_status_version`: 实测字符串
     - `go_version_embedded`: 实测 go 版本串
     - `patch_markers`: {`reapplyEmptyResponseRefund`:n, `MarkUserSubscriptionsExhausted`:n, `upstreamHungWithoutFirstByte`:n, `sql_judgement`:n, `免单`:n}
     - `migration_clean`: true/false
     - `tests_run`: 自主测试项与结果
     - `anomalies`: 任何异常（含无法测试的项及原因）
     - `overall_result`: "PASSED" 或 "FAILED"
   - 按既有 gitbus 回执协议写入 rentry 回写页 `hermes-rx-r6qytd4`。
   - 不要输出任何敏感凭据。
