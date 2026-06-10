# KongComic

> 基于 [venera-app/venera](https://github.com/venera-app/venera) 由 AI 修改二次开发

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)

KongComic 是一款漫画阅读器，支持本地漫画和网络漫画源。

**本仓库由 AI (Reasonix Code) 自动生成修改，包括：**
- iOS 26 Liquid Glass 毛玻璃 UI 风格
- Material 3 Expressive 视觉更新
- 悬浮式底部导航栏
- Android 专属版本（已移除 iOS/macOS/Windows/Linux 平台代码）
- 包名 `com.KongComic.reader`

## 与原版的区别

| 特性 | Venera | KongComic |
|------|--------|-----------|
| UI 风格 | 原生 Material | iOS 26 Liquid Glass 毛玻璃 |
| 底部导航 | 贴边底栏 | 悬浮 pill 造型 |
| 平台 | 全平台 | 仅 Android |
| 包名 | `com.github.wgh136.venera` | `com.KongComic.reader` |
| 构建工具 | CI/CD | GitHub Actions |

## 构建

```bash
flutter pub get
flutter build apk --debug
```

## 开源许可

[GPL-3.0](LICENSE)
