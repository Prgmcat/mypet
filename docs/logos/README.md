# 应用图标

当前方案：**🐾 两个蓝色猫爪印**（直接使用 App 内 AI 对话的 Noto 猫爪 emoji 字形）。

## 文件

- `logo-paw-emoji.png`：512×512 设计稿（米白底）
- `logo-paw-emoji-transparent.png`：透明底猫爪，用于自适应图标前景

## 配色

| 用途 | 色值 |
|---|---|
| 猫爪 | `#176BC6` |
| 背景 | `#FBF7F1` |

猫爪字形来自 Android 系统 `NotoColorEmoji.ttf`（U+1F43E），用浏览器按矢量 COLR 渲染成高清 PNG，颜色与 App 内一致。

## Android 资源

- `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`：传统圆角方形图标（米白底 + 猫爪）
- `.../ic_launcher_foreground.png`：自适应图标前景（108dp 画布，安全区内）
- `mipmap-anydpi-v26/ic_launcher.xml`：自适应图标
- `values/colors.xml`：`ic_launcher_background` = `#FBF7F1`

## 历史方案

`preview.png`、`preview-cats.png`、`preview-calico.png`、`preview-minimal.png`、`preview-paw.png` 为早期设计探索，仅作存档，不再用于构建。
