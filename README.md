# 喵了个咪

小规模多用户自托管宠物档案 App：Android（Flutter）+ Go 单二进制服务端 + SQLite。

## 当前进度

已完成第一阶段主闭环（S1–S4 的核心 P0）：

- **账号与权限**：管理员初始化、邀请码、注册/登录、设备 Token、改密、重置码、用户禁用/启用、登录失败锁定、邀请码列表/作废。
- **宠物档案**：多宠建档、编辑、删除/恢复接口、电子身份证号、证件卡二维码（编码临时访客链接）、过敏/慢性病/长期用药、我的/共享标识。
- **健康记录**：疫苗、驱虫、体检、病历、用药、洗护；附件上传/查看；时间线筛选；体重记录、体重曲线、档案体重回写。
- **OCR**：拍照/相册、端侧中文识别（ML Kit）、指标解析、低置信可编辑、确认后写入体检记录并保留原图；失败可手动填写。
- **AI**：首页全局入口，不需要先选宠物；多厂商配置（OpenAI 兼容 / Anthropic）、Key 仅本机、连接测试、流式对话、按会话切换服务商、档案上下文、多宠识别、L1–L3 风险提示与 L3 就医卡、语音输入、会话历史、有用/无用反馈、对话式记录草稿。AI 设置页只显示已配置的服务商，当前使用项高亮。
- **边聊边记**：聊天中陈述的体重（支持“斤”换算）、症状/就医、换粮/饮食会自动写入对应宠物档案（体重记录、病历、饮食记录），卡片展示并可一键撤销；本地规则优先，规则未命中时再用模型抽取；无法确定宠物时让用户选择或忽略。
- **提醒**：疫苗/驱虫/体检/生日规则、提前偏移、`occurrenceKey` 去重、完成/稍后/跳过、完成后自动生成记录并重算下次、Android 本地通知（含重启恢复）。
- **共享**：按精确用户名邀请成员（只读/共同照护）、访客链接（有效期、4 位口令、撤销）、免登录 H5（摘要、待办、完成打卡、拍照反馈）、访客操作审计。
- **设置与备份**：服务器状态、设备管理、管理员设备总览、改密、备份/恢复/自检 CLI、隐私与 AI 免责说明。
- **离线只读**：宠物列表、宠物详情记录与提醒中心在断网时回退到本机缓存，并提示缓存日期；退出登录清除缓存。

已通过：

- `go test ./...`、`go vet ./...`、服务端全链路 E2E（邀请码 → 注册 → 建档 → 记录 → 提醒 → 共享 → 访客 → 撤销 → 登录锁定）。
- `flutter analyze`、`flutter test`（AI 流式解析、风险分级、档案上下文）、`flutter build apk`（debug + release）。

尚未完成（后续迭代）：记录/宠物回收站 UI、通知栏内直接“完成/稍后”操作、访客操作审计 UI、多页/批量 OCR、症状图片识别、PDF 导出、成长相册、饮食/换药、完整离线写队列。

## 目录

```
app/       Flutter Android 客户端
server/    Go 服务端
docs/      需求与开发计划
```

## 环境

本机已验证：

- Flutter 3.16.8 / Dart 3.2.5
- Android SDK 35，build-tools 35.0.1（Release 需 JDK 17）
- JDK 17：`C:\Users\Prgmcat\sdk\jdk-17.0.20.1+1`（项目 `app/android/gradle.properties` 已指定）
- Gradle 8.9（已配置腾讯镜像）
- Go 1.27：`C:\Users\Prgmcat\sdk\go\bin`（已加入用户 PATH）

换机器需要安装 Flutter、Android SDK、JDK 17、Go；Gradle 会按 `app/android/gradle/wrapper/gradle-wrapper.properties` 下载。

## 启动服务端

```bash
cd server
go run ./cmd/mypet init -data ./data -username admin -password 'Passw0rd!'
go run ./cmd/mypet serve -data ./data -addr 0.0.0.0:8787
```

创建邀请码（也可在 App「设置 → 用户管理」里操作）：

```bash
go run ./cmd/mypet create-invite -data ./data -ttl-hours 168 -max-uses 1
```

### 备份、恢复与自检

```bash
# 打包 SQLite + uploads 为 zip（建议先停服务，或低峰期执行）
go run ./cmd/mypet backup -data ./data -out ./backup

# 恢复：会自动先备份当前数据，并保留旧数据库
go run ./cmd/mypet restore -data ./data -from ./backup/mypet-YYYYmmdd-HHMMSS.zip

# 检查数据库完整性、用户/宠物/记录数量、附件目录可写
go run ./cmd/mypet doctor -data ./data
```

恢复会替换 `data/mypet.db` 与 `data/uploads`，旧数据保留为 `*.pre-restore-<时间戳>`；请先停止服务端。

默认数据目录是 `server/data/`，已在 `.gitignore` 中忽略。SQLite 使用 WAL，附件位于 `server/data/uploads/`。

## 运行 Android App

模拟器（默认服务器地址 `http://10.0.2.2:8787`）：

```bash
cd app
flutter pub get
flutter run
```

Release APK（按 ABI 拆分，单个 ≤ 45 MB）：

```bash
flutter build apk --release --split-per-abi
# 产物：
# app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   (~30 MB)
# app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (~24 MB)
# app/build/app/outputs/flutter-apk/app-x86_64-release.apk      (~32 MB，模拟器)
```

> 注意：`flutter build apk`（不拆分）会包含所有 ABI 和 ML Kit 全量原生库，体积约 50 MB；分发请用 `--split-per-abi`。Debug APK 还包含 Vulkan 校验层，体积异常大，不用于分发。

真机：手机与服务器同一局域网，在登录页把服务器地址改成运行 Go 服务的电脑 IP，例如 `http://192.168.1.10:8787`。开发版允许 HTTP 明文（`android:usesCleartextTraffic="true"`），正式环境应使用 HTTPS 或 Tailscale/WireGuard。

## 权限说明

- 通知：本地照护提醒；Android 13+ 首次启动会请求通知权限，拒绝后仍有应用内红点与提醒中心。
- 相机/相册：拍照记录与化验单 OCR；使用系统相机/相册选择器。
- 麦克风：AI/语音输入；拒绝后降级为键盘输入。
- 网络：访问自托管服务器与用户配置的模型厂商。

## AI 与 OCR

- **AI Key 只保存在 Android Keystore（按账号隔离）**，服务端不接收、不代理；界面只显示末 4 位。
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、通义千问、Moonshot、智谱、Gemini 兼容端点）与 Anthropic Messages API；Base URL 与模型可自定义。
- 首次提问前需在「设置 → AI 服务设置」配置 Key；未配置时不会发起请求。
- AI 回答标注“AI 生成，仅供参考”；本地红线词库独立展示 L3 就医卡，不依赖模型输出。
- OCR 使用 ML Kit 端侧中文识别，图片不上传云端；结构化结果必须用户确认后才写入，失败可手动填写。

## 账号流程

1. 服务端 `init` 创建管理员。
2. 管理员登录 App，在「设置 → 用户管理」创建邀请码。
3. 新用户用邀请码注册，注册后自动登录。
4. 用户只能访问自己的宠物；所有者可按用户名邀请成员或创建访客链接。
5. 管理员默认只能看到用户列表与账号状态，看不到用户宠物与记录。

## 备注

- 服务端默认监听 `0.0.0.0:8787`，公网访问请使用 Tailscale/WireGuard 或 HTTPS 反向代理。
- 单实例默认适合 ≤50 用户；SQLite 使用 WAL、单写者、短事务。
- 访客链接 Token 仅存哈希，撤销/过期后立即失效；口令连续错误 5 次锁定 10 分钟。
- 数据导出、回收站 UI、多页 OCR 等 P1 能力尚未实现。
