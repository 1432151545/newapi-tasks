# T-MUSE-AGENT02：独立 SG 验收后的返修
nonce: NONCE-MUSE-AGENT02-20261002
由 Muse 原生 Agent 完成，不启动 Codex，不改服务。

上一任务 T-MUSE-AGENT01 的四文件 SHA256 全部通过香港核验，SG Python3.11.2 重跑原有18个测试全部通过。但独立追加检查失败：
eligible({'id':'bad-date','type':'agent','target':'muse','created':'2026-02-30T12:00:00Z'}, '2026-02-01T00:00:00Z', [], '2026-03-01T00:00:00Z') 返回 True，要求 False。

请在上一工作目录的复制件上修复 task_guard.py 的真实日历合法性校验。使用标准库 datetime 校验真实日期，并严格完整匹配 YYYY-MM-DDTHH:MM:SSZ；末尾换行、非闰年2月29、2月30、4月31均拒绝，合法闰年2月29接受。expires 字段显式存在但为 None 时也拒绝（有字段就必须是有效时间）；缺少 expires 可接受。以上规则同样适用 created、enablement、now。
添加针对这些问题的测试，保留原有测试（如原有测试错误，应说明并纠正，不为保留错误预期放宽规则）。运行实际 unittest。

如上一任务，回传 task_guard.py、test_task_guard.py、实际测试日志、manifest.json；nonce/文件SHA256/字节数齐全。使用已有rentry内联回传，状态 executed_transport_pending，由香港核验后代写私有回执库，再去SG独立测试。无需PAT，不反复尝试SSH，不输出凭据。不要把queued视为执行成功。
