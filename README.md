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
