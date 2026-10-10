# T-MUSE-TRANSPORT01：只修回执补发，不重复编码
nonce: NONCE-MUSE-TRANSPORT01-20261002

香港已确认T-MUSE-AGENT02尚未进入rentry，不能独立验收。香港已完整备份并瘦身当前回写页，保留AGENT01及心跳，textarea闭合标签现在约26KB（此前页面更大）。

本任务由Muse原生Agent执行，不用Codex，不碰生产/服务/watchdog。首先检查AGENT02本地产物/完整REC，沿用原nonce NONCE-MUSE-AGENT02-20261002，复核文件hash，不重做task_guard实现。将AGENT02从running标为executed_transport_pending（若实际工作确已完成），避免重复编码。若原worker还存活，不抢锁，只协调其补发。

修复补发器：不要使用read()读全页失败就丢掉已收内容。使用同一cookiejar opener GET /edit，按小块read1或read读取，有异常（包括IncompleteRead的partial）保留已有内容，限定总时长；从已读前部提取csrfmiddlewaretoken，保留cookies。读取不到textarea闭合标签时只保留完整且可解码校验sha的REC行，不保留截断的半条REC。读不到历史完整内容不阻止补发：本次运输允许只写新的完整AGENT02 REC与已读且校验通过的记录，香港已备份旧页。新REC放最前。不要把整个HTML当作textarea或回写内容。
POST沿用现有/api/edit/<slug>协议、Referer和Cookie，edit_code只读沙箱现有本地配置或已持有上下文，不打印、不提交Git。POST响应检查status；网络异常不能直接判定成功/失败，随后GET /edit容错读取，确认AGENT02 task_id/nonce/整体sha及完整data匹配；若确认未写再重试，有限重试。
优先复用现有worker代码里的_read_tolerant、textarea_full及rentry写入函数，检查签名和行为后调用，不能只重复旧的严格读法5次。不要尝试SSH推git或索取PAT。
若仍失败，报告具体阶段GET token/POST响应/回读确认及HTTP状态、已读字节数、异常类别（禁止凭据）；保留完整待发送REC。下一轮只补发。这个运输任务本身的回执可简短，不要把失败误标SG验收通过。
