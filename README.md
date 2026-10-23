# 喵了个咪

小规模多用户自托管宠物档案 App：Android（Flutter）+ Go 单二进制服务端 + SQLite。

## 当前进度

已完成第一阶段骨架：

- Go 服务端：SQLite 建库/迁移、管理员初始化、邀请码、注册/登录、设备 Token、修改密码、密码重置码、用户列表/禁用、宠物 CRUD、健康检查、备份 CLI。
- Android App：登录、邀请码注册、宠物列表、建档、详情、编辑、删除、管理员创建邀请码/查看用户。
- 已通过：`go test ./...`、`flutter analyze`、`flutter build apk --debug`、Android 模拟器真机级注册/登录/建档冒烟。

下一阶段：健康记录、附件、OCR、AI 会话/语音、本地提醒、成员共享/访客 H5。

## 目录

```
app/       Flutter Android 客户端
server/    Go 服务端
docs/      需求与开发计划
```

## 环境

本机已验证：

- Flutter 3.16.8 / Dart 3.2.5
- Android SDK 35，build-tools 35.0.1
- JDK 17：`C:\Users\Prgmcat\sdk\jdk-17.0.20.1+1`（项目 `app/android/gradle.properties` 已指定）
- Gradle 8.9（已配置腾讯镜像）
- Go 1.27：`C:\Users\Prgmcat\sdk\go\bin`（已加入用户 PATH）

如果换机器，需要安装 Flutter、Android SDK、JDK 17、Go；Gradle 会按 `app/android/gradle/wrapper/gradle-wrapper.properties` 下载。

## 启动服务端

```bash
cd server
go run ./cmd/mypet init -data ./data -username admin -password 'Passw0rd!'
go run ./cmd/mypet serve -data ./data -addr 0.0.0.0:8787
```

创建邀请码（也可在 App 管理员菜单里创建）：

```bash
go run ./cmd/mypet create-invite -data ./data -ttl-hours 168 -max-uses 1
```

备份：

```bash
go run ./cmd/mypet backup -data ./data -out ./backup
```

默认数据目录是 `server/data/`，已在 `.gitignore` 中忽略。SQLite 使用 WAL，附件后续会放在 `server/data/uploads/`。

## 运行 Android App

模拟器（默认服务器地址 `http://10.0.2.2:8787`）：

```bash
cd app
flutter pub get
flutter run
```

构建 APK：

```bash
flutter build apk --debug
# 产物：app/build/app/outputs/flutter-apk/app-debug.apk
```

真机：手机和服务器在同一局域网，把登录页的服务器地址改成运行 Go 服务的电脑 IP，例如 `http://192.168.1.10:8787`。当前开发版允许 HTTP 明文（`android:usesCleartextTraffic="true"`），正式环境应使用 HTTPS。

## 账号流程

1. 服务端 `init` 创建管理员。
2. 管理员登录 App，右上角菜单创建邀请码。
3. 新用户用邀请码注册，注册后自动登录。
4. 用户只能访问自己的宠物；共享能力下一步接入。

## 备注

- 当前只实现了第一阶段骨架，尚未接入 OCR/AI/提醒/共享 H5。
- Flutter 3.16 较旧，依赖已按 Dart 3.2 兼容版本锁定；后续可评估升级。
- 服务器默认监听 `0.0.0.0:8787`，公网访问请使用 Tailscale/WireGuard 或 HTTPS 反向代理。
