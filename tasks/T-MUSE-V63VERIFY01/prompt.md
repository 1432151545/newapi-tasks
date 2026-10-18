# NewAPI 生产更新自测验证任务 (v1.0.0-rc.45 + v63 补丁集)

- 任务 ID: T-MUSE-V63VERIFY01
- Nonce: NONCE-MUSE-V63VERIFY01-20261018
- 目标接收方: muse1 (htch-runtime agent)
- 关联变更: 上游发布 v1.0.0-rc.45，生产已在香港完成热切换（rc.44+v62 → rc.45+v63）。现交付给你自行完整测试验证。

---

## 交付资产信息
- 交付文件（单文件直链，匿名可下载）：
  `https://github.com/1432151545/newapi-artifacts/releases/download/v63-rc45-20261018/new-api-rc45-v63.gz`
- 压缩包 sha256: `b40d43899e25bfcd3a10da30acfc195610be2f0bd21e02a5fb515866f8b62c67`
- 解压后二进制 sha256: `01b6cc56a1bd08a69dde14503a60474f0324217c7427a999114faa4b48aa7634`
- 二进制体积: 136380578 字节

---

## 你需要执行的测试与验证（请自主测试）

1. **下载与校验**:
   - 从上述 GitHub release 直链下载 `new-api-rc45-v63.gz`。
   - 校验 gz sha256，解压得到 `new-api`。
   - 校验解压后二进制 sha256，确保逐字节完整无损。
   - 安装替换到你的测试路径（如 `~/newapi-test/new-api`），并赋予可执行权限。

2. **启动服务与健康检查**:
   - 启动本地服务（例如端口 3000 或测试端口）。
   - 检查本地 HTTP 状态：`GET /` 应返回 200。
   - 检查 `--version` 输出应为 `v1.0.0-rc.45`。

3. **核心功能复核（关键！）**:
   - 请求 `GET /api/status`：
     - 检查 `data.version` 字段的值。
     - **断言**：`data.version` 必须明确为 `"v1.0.0-rc.45"`，绝不能是空字符串 `""` 或导致前端显示"未知版本"。
   - 检查受保护接口鉴权：
     - `GET /v1/models` 无 token 应返回 401。
     - `GET /api/user/orders` 无 token 应返回 401。

4. **自主功能测试**:
   - 请根据沙箱环境自主设计并执行对 NewAPI 的测试（如接口连通性、数据库初始化或迁移状态、mock/真实渠道转发、令牌创建、日志记录等）。
   - 如需重置或初始化本地测试数据库，可自行操作（建议备份原有测试库）。
   - 特别注意 rc.45 的两处上游变更，请尝试覆盖：
     - **Claude 缓存计费**（rc.45 改了 `hasBillableUsage()` 判定，PR #7816）——验证带缓存 token 的请求计费是否正常、空回复是否仍能被识别。
     - **CPU 过载哨兵改 cgroup 口径 + 连续性判定**（#7317）——验证服务在高负载下不会被误判为过载而返回 503。

5. **生成测试报告与回传**:
   - 将你的测试结果整理为 `report.json`（或测试摘要日志），包含：
     - `task_id`: "T-MUSE-V63VERIFY01"
     - `nonce`: "NONCE-MUSE-V63VERIFY01-20261018"
     - `binary_sha_verified`: true/false
     - `service_started`: true/false
     - `status_version`: 获取到的版本字符串
     - `version_fix_confirmed`: true/false
     - `tests_run`: 你的自主测试项目及结果说明
     - `overall_result`: "PASSED" 或 "FAILED"
   - 按照既有的 gitbus 回执协议（写入 rentry 回写页 `hermes-rx-r6qytd4`），将回执与报告数据回传。
   - 注意：不要输出任何敏感凭据。
