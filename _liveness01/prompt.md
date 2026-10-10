# T-MUSE-LIVENESS01：原生执行链心跳
nonce: NONCE-MUSE-LIVENESS01-20261002

不要修改new-api、watchdog或生产服务，不新建调度器。不启动外部Agent。
请调整现有hermes-agent-executor的任务指令：空闲时每15分钟通过现有rentry回写页发布一条HB，格式 HB|ts=<实际运行UTC YYYY-MM-DDTHH:MM:SSZ>|role=muse-native-agent|host=<host>|task=<当前任务或idle>|pending=<待补发回执数量>。每次只保留本角色最新一条HB，保留完整REC，采用容错读写，不要求读完整HTML。心跳仅表示Agent实际成功运行并成功回传，不使用cron计划时间充当心跳。
保留现有5分钟Agent检查任务。暂停/休眠后恢复时先补发已有完整产物，再续做任务；已完成编码但回传失败标executed_transport_pending，不重复编码。
这次首次写出心跳，并用本任务REC说明实际配置改动、恢复行为和已知限制。不能确认runtime会唤醒休眠沙箱时明确说明，不能宣称永不休眠。不要人为休眠或停止沙箱。
香港将每5分钟读心跳，最后一次成功心跳超过30分钟仅告警一次“执行链失联，休眠/调度/回传原因未知”，恢复仅通知一次。禁止泄露任何凭据。回传后等香港验收。
