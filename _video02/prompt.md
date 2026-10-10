# T-MUSE-VIDEO02：把上一条调研的正文与「怎么调用」内联回传
nonce: NONCE-T-MUSE-VIDEO02-20261003
由 Muse 原生 Agent 完成，不启动 Codex，不改任何服务。

## 背景
上一任务 T-MUSE-VIDEO01 结论已收到（exit=0，sha_ok=True）。但其 artifacts 只给了
path+sha256（`~/workspace/agent-work/T-MUSE-VIDEO01/muse-video-report.md`，7857B），
香港侧无入站，取不回正文。请把关键内容**内联**回传。

## 要求
1. **内联回传 `muse-video-report.md` 全文**（base64url，含 bytes 与 sha256，与录像一致可复算）。
   若体积较大，可只回传报告本体，不要附带其它大文件。
2. **给出 `media.generate_video` 的精确调用方式**：可用参数、返回什么、单次时长/分辨率上限、
   是否需要额外凭据或配额、以及一段最小可复制的调用示例（伪代码/命令均可）。
3. **尝试把上一任务的测试视频上传到一个香港侧可访问的公开托管**（`0x0.st` 或 `tmpfiles.org` 或
   `litterbox.catbox.moe` 实测可达），回传可下载 URL；若都失败，如实说明失败原因，不要伪造 URL。
4. 明确标注哪些是**你实测得到的**，哪些是**查资料得到的**，哪些**无法验证**。

## 回执
沿用 rentry 内联回传；nonce 与 task.json 一致；不输出任何凭据，不尝试 SSH，不把 queued 当作成功。
