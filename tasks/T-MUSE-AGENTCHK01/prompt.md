# Muse 原生 Agent 存活探针（只读，极小）

任务 ID: T-MUSE-AGENTCHK01
nonce: NONCE-MUSE-AGENTCHK01-20261010

这是一次**只读存活探针**，不做任何修改、不写任何配置、不碰 new-api/watchdog/生产环境/历史任务。

## 要做的事
1. 采集本机最小状态：`hostname`、`date -u +%FT%TZ`、`nproc`、`df -h $HOME | tail -1`、
   以及 `ps -eo pid,etimes,args | grep -E "muse_git_poller|bus_worker|watchdog" | grep -v grep`（可为空）。
2. 写下你**上次实际处理任务的时间**（若 `~/.hermes-gitbus/agent_sentry.json` 或日志里有迹可循）。
3. 就上面这些生成一个 `report.json`，字段：`task_id`、`nonce`、`host`、`utc`、`nproc`、`home_free`、
   `processes`（数组）、`last_agent_activity`（字符串或 null）。
4. 按既有 rentry 回写协议把 `report.json` 内联回传（base64url + 独立 SHA256），REC 放页面最前，
   容错读取（读到多少算多少）。不要输出任何凭据，不要把凭据提交到公开库。

## 边界
- 纯只读；不安装、不下载、不改调度器、不碰生产。
- 若某个命令不存在，字段写 `null` 即可，不要为了补全而安装工具。
- 交付不了就如实记录阻断并 handoff，**不要伪造成功**。