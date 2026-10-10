# T-MUSE-VIDEO01：调研「Muse 现在能不能生成视频，怎么弄」
nonce: NONCE-T-MUSE-VIDEO01-20261003
由 Muse 原生 Agent 完成，不启动 Codex，不改任何服务，只做调研与方案输出。

## 背景
用户想知道：Meta Muse（muse.ai 个人 AI Agent）现在能不能生成视频？具体怎么操作？
这是一次只读调研任务，不需要你写代码或部署任何东西。

## 请调查并回答以下问题（能联网查证的就查证，查不到的如实标注"无法验证"）
1. **Muse Video 模型现状**：Meta Superintelligence Labs 的 Muse Video（2026-07-07 预览）当前是否已正式开放？
   有没有公开 API / 定价 / 发布日期？还是仍在闭测？
2. **Muse 应用本身**：Muse 官方列出的能力里，视频生成（区别于图像生成）是否已上线？
   如果上线，在哪个平台入口（Muse App / Meta AI App / Vibes / meta.ai）？
3. **当前可用的替代路径**：如果 Muse Video 还没开放，现在普通人/开发者生成 AI 视频有哪些真正可用的选项
   （如 Meta AI/Vibes 的 vibe 图生视频、Veo 3、Sora 2、其它免费/低成本文生视频服务）？
4. **本沙箱（这台 2C/7.9G、无 GPU、无 docker、只能 HTTPS 出站的 Linux 沙箱）能否直接生成视频？**
   比如有没有无需 GPU、纯 API/CLI 的文生视频服务可以从这里调用？需要哪些凭据？

## 输出要求
- 把调研结论写成一份 Markdown 报告 `muse-video-report.md`，结构清晰、区分【已确认事实】/【推测】/【无法验证】。
- 报告必须包含一个"如果现在就想生成视频，最实际可行的 3 条路径"小节，按可行性排序，注明每条的
  门槛（要不要账号/付费/API key/国家地区限制）。
- 回传文件：muse-video-report.md，附带 sha256 与字节数；nonce 必须与 task.json 一致。
- 用现有 rentry 内联回传，状态 executed_transport_pending；不输出任何凭据，不反复尝试 SSH，不要把 queued 视为执行成功。
