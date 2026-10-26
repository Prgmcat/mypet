# 应用图标

当前方案：**C 对话气泡 + 爪印**（突出 AI 助手与宠物）。

## 文件

- `logo-c-chat.png`：512×512 设计稿（米白底）
- `logo-c-transparent.png`：仅气泡与爪印，透明底，用于自适应图标前景
- `logo-c-mockup.png`：圆形图标效果预览
- `preview.png`：四个候选方案的对比图（A 爪印 / B 猫咪 / C 对话 / D 档案）

## 配色

| 用途 | 色值 |
|---|---|
| 主色（气泡） | `#8A4B08` |
| 背景 | `#FBF7F1` |
| 爪印 | `#FBF7F1` |
| 备选绿色（D 方案） | `#3E6B4F` |

## Android 资源

- `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`：传统方形图标
- `.../ic_launcher_foreground.png`：自适应图标前景（108dp 画布，安全区内）
- `mipmap-anydpi-v26/ic_launcher.xml`：自适应图标
- `values/colors.xml`：`ic_launcher_background`
