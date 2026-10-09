# newapi-tasks — 公共任务通道（零凭据）

HK（Hermes）**发布任务** → 沙箱侧轮询器（`git pull`，匿名 HTTPS）**认领并执行** → 结果经
rentry 回写页回传 → HK **独立核验**并归档到 `results/`。

## 为什么用 git
- 版本历史 / 可回滚 / 可重放；无 60k 内联上限；不依赖 rentry 渲染页爬取
- 读取零凭据（公开库，匿名 HTTPS 只读）
- 回写仍走 rentry 回写页（同样零凭据）——**git push 永远需要凭据，这是刻意的分工**

## 目录
```
tasks/<id>/task.json      任务定义
tasks/<id>/script.sh      机器任务（type=script）载荷
tasks/<id>/prompt.md      代理任务（type=agent）载荷
worker/muse_git_poller.py 沙箱侧轮询器（自更新：每轮先 pull 再自比对）
worker/install.sh         一键安装/更新（clone + 安装 + 定时 + 立即跑一次）
results/<id>.json         HK 核验通过后的结果归档
```

## task.json 格式
```json
{
  "id": "T-XXXX",
  "type": "script | agent",
  "target": "any | muse | sg",
  "nonce": "NONCE-...",
  "timeout": 900,
  "created": "2026-10-02T00:00:00Z",
  "note": "人类可读说明",
  "files": {"script.sh": "<sha256>"}
}
```
- `type=script`：沙箱执行 `script.sh`（先校验 sha256），stdout/stderr 作为 `script.log` 回传
- `type=agent`：prompt 先入队 `~/.hermes-gitbus/agent_inbox/<id>.md`；若配置了
  `BUS_EXEC`（命令模板，`{prompt_file}` 占位）则调用执行器
- `target`：`any` 所有轮询器可认领；`muse`/`sg` 仅对应角色；其他值一律跳过（不烧任务）

## 结果回执（rentry 回写页，与既有总线契约一致）
```
REC|task=<id>|nonce=<n>|exit=<rc>|type=<t>|ts=<iso>|host=<h>|sha=<sha256(结果JSON)>|data=<base64url(结果JSON)>
```
- `sha` = sha256(结果 JSON 的原始字节)；`data` = 同份 JSON 的 base64url（去 padding）
- 单条 `data` ≤ 60000 字符；超出时截断并标 `truncated/original_size`（大批量产物后续版本支持分片）
- 合并回写：只替换自己的 `REC|task=<id>|` 行，保留其他 REC/HB（REC≤10、HB≤3）

## 约定
- **本仓库公开**：任务内容不得含任何密钥/凭据/隐私数据
- 任务文本里如需保密信息，只写占位符，真实值由沙箱侧从既有通道（指针页）获取
- 轮询器零凭据：读库匿名、回写用回写页 edit_code（从指针页运行时获取，本地缓存兜底）

## 多账号（2026-10-09）

两台 Muse 沙箱（不同账号）共用本任务库，靠 **role** 区分，互不抢任务：

```bash
# muse1（默认，等价于旧行为）——不用做任何事
# muse2（第二台沙箱）——引导时显式带角色
BUS_ROLE=muse2 bash bootstrap.sh
```

角色决定：认领 `target==角色` 或 `target==any` 的任务；心跳的 `role` 字段。
**不传 BUS_ROLE 的第二台机器会退化成第二个 muse，与 muse1 抢同一批任务** —— 所以
bootstrap.sh 有硬断言：非法角色退出 2；状态目录里已有别人台账时退出 3。

### 回写页必须一账号一页（否则会吞掉对方的回执）

沙箱出口代理把响应掐在 ~23KB，而回写页是「读-改-写」：读不全 → 合并时把看不见的
REC 行整行丢掉。实测：共用一页时，第二台机器写一次回执，页面从 10 条 REC 掉到 4 条。
所以：

- 指针页 `hermes-muse-ptr` 支持**按角色**的字段：`outbox_slug_<role>` / `outbox_code_<role>`，
  没有则回退通用 `outbox_slug` / `outbox_code`（单账号行为不变）。
- 每个账号自己的回写页凭据，放在对应 `outbox_*_<role>` 字段里；引导时无需把凭据写进粘贴文本。
- HK 侧核验 `verify_rec.py` 会一并读 `/root/muse-deploy/bus-info*.txt` 里列出的所有回写页。

### 发布任务到指定账号

```bash
./pub.sh <id> <type> <target> <nonce> <timeout> <dir> [note]
# target=muse2 就只有 muse2 会认领；target=muse 只有 muse1
```
