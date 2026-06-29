# KongComic

> A comic reader based on [venera-app/venera](https://github.com/venera-app/venera), deeply modified by AI (Reasonix)

[![Flutter](https://img.shields.io/badge/Flutter-3.44.0-blue?logo=flutter)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/SkyAlice-source/KongComic-android)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.1.6-blue)](https://github.com/SkyAlice-source/KongComic-android/releases)
[![GitHub Stars](https://img.shields.io/github/stars/SkyAlice-source/KongComic-android)](https://github.com/SkyAlice-source/KongComic-android/stargazers)

---

## 📖 Table of Contents

- [Introduction](#-introduction)
- [Features](#-features)
- [Installation](#-installation)
- [Usage Guide](#-usage-guide)
- [Development Setup](#-development-setup)
- [Project Structure](#-project-structure)
- [Contributing](#-contributing)
- [License](#-license)
- [Acknowledgments](#-acknowledgments)

---

## 📖 Introduction

KongComic is a cross-platform comic reader built with Flutter, derived from the [Venera](https://github.com/venera-app/venera) project and deeply modified with AI assistance. The app supports multi-source comic aggregation, local comic management, and online reading.

### 🖼️ Screenshots

<div align="center">
  <img src="doc/Screenshot_20260625_030823.png" width="280" alt="Home (light)" />
  &nbsp;&nbsp;
  <img src="doc/Screenshot_20260625_030912.png" width="280" alt="Home (dark)" />
  <br/>
  <em>Home page — light theme (left) and dark theme (right)</em>
</div>

---

## ✨ Features

### 🏠 Home
- Banner card carousel with auto-switching
- Comic info panel: title, author, reading progress, total episodes, "Read Now" button
- Quick access: Follow Updates, Local, Image Favorites, Comic Source

### 🗺️ Navigation
- 5 tabs: Categories / Favorites / Home / Explore / History
- Active state: purple circle + purple icon + bold text
- Floating glass bottom bar with rounded corners

### 🔍 Search
- Multi-source search + aggregated search
- Direct ID jump
- Tag suggestions with debounce
- Search history with individual deletion

### 📚 Comic Source System
- JavaScript-based comic source plugin system
- Load sources from remote repositories
- Built-in source configuration manager

### 📖 Reader
- Touch to turn pages (30% left/right zones, 40% center menu)
- Progress bar with ShaderMask dual-color text
- Supports CBZ / CB7 / EPUB / PDF formats
- Image preload concurrency control (prevents OOM)

### 🎨 UI
- Geist-inspired flat design
- HugeIcons (5000+ line icons) replacing all FluentIcons/Material Icons
- Light/Dark dual theme

### 📦 Download & Local Management
- Comic download support (CBZ packaging)
- Local comic import (directory structure and archives)
- Download progress notification throttling (500ms interval)

### 🔄 Backup & Restore
- Export/import includes: history, favorites, settings, cookies, source scripts, custom covers

### ⚙️ Settings
- 9 categories: Reader / Appearance / Explore / Favorites / Network / Download / Import / General / About
- Sorted by usage frequency
- Language selector (System / Simplified Chinese / Traditional Chinese / English)

---

## 🔧 Installation

### 📱 Method 1: Download Pre-built APK (Recommended)

1. Visit the [Releases](https://github.com/SkyAlice-source/KongComic-android/releases) page
2. Download the APK matching your device architecture:

| APK File | Size | Target Device |
|----------|------|---------------|
| `KongComic-1.1.6-arm64-v8a.apk` | ~17 MB | Modern Android phones (ARM64) |
| `KongComic-1.1.6-armeabi-v7a.apk` | ~16 MB | Older Android devices (ARM32) |
| `KongComic-1.1.6-x86_64.apk` | ~17 MB | Emulators / x86 tablets |
| `KongComic-1.1.6-universal.apk` | ~41 MB | All architectures (universal) |

3. Transfer the APK file to your Android device
4. Open the APK file on your device and follow the prompts to install
   - If prompted with "Install from unknown source", please allow this installation in system settings

### 🛠️ Method 2: Build from Source

#### Requirements

| Dependency | Version | Notes |
|-----------|---------|-------|
| Flutter SDK | 3.44.0+ | [Install Guide](https://docs.flutter.dev/get-started/install) |
| Dart SDK | 3.8.0+ | Installed with Flutter |
| Android SDK | 21+ | API Level 21 (Android 5.0) or above |
| Git | Latest | For fetching dependencies and submodules |

#### Build Steps

```bash
# 1. Clone the repository
git clone https://github.com/SkyAlice-source/KongComic-android.git
cd KongComic-android

# 2. Get dependencies (git dependencies like flutter_qjs are fetched automatically on first run)
flutter pub get

# 3. Build Release APK (split per ABI)
flutter build apk --release --split-per-abi

# Or use the following command to skip build dependency validation (recommended)
flutter build apk --release --android-skip-build-dependency-validation
```

After building, the APK files are located at:
```
build/app/outputs/flutter-apk/KongComic-{version}-{abi}.apk
```

#### Run Directly (Development/Debug)

```bash
# Connect an Android device or start an emulator, then run
flutter run
```

### 🪟 Windows Platform Build (Experimental)

```bash
# Build Windows desktop application
flutter build windows --release
```

> ⚠️ The Windows version is experimental; some features may not be available.

---

## 📘 Usage Guide

### 🚀 Quick Start

#### 1. First Launch

After first launch, it is recommended to configure in the following order:

1. **Set up comic sources**: Go to "Explore" → tap the "+" in the top-right → add a comic source repository URL
   ```
   https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json
   ```
2. **Select comic sources**: Enable the data sources you need from the source list
3. **Configure download path**: Go to "Settings" → "Download" → set local storage path

#### 2. Search and Read

```
# Basic search flow
1. Tap the "Search" tab at the bottom
2. Enter keywords or comic ID
3. Select a comic from search results
4. View details → select chapter → start reading
```

#### 3. Download Comics

1. Tap the "Download" button on the comic detail page
2. Select the chapters you want to download
3. Configure in "Settings" → "Download":
   - Concurrent download threads
   - Whether to package as CBZ
   - Whether to delete original folder after CBZ packaging

> 💡 Downloaded CBZ files are named: `<comic name> - <chapter name>.cbz` (e.g., `One Piece - Ch.01.cbz`)

#### 4. Local Comic Import

KongComic supports importing local comic files in the following formats:

**Supported archive formats**: `.cbz`, `.cb7`, `.zip`, `.7z`

**Directory structure specification**:

Without chapters:
```
comic_directory/
├── cover.jpg       # Cover (optional)
├── img1.jpg
├── img2.jpg
└── ...
```

With chapters:
```
comic_directory/
├── cover.jpg       # Cover (optional)
├── Chapter 1/
│   ├── img1.jpg
│   └── img2.jpg
├── Chapter 2/
│   ├── img1.jpg
│   └── img2.jpg
└── ...
```

Import steps:
1. Place comic files/directories in the configured local storage path
2. Open the app → "Local" → tap "Import"
3. Select "Scan local files" or "Restore local downloads"

#### 5. WebDAV Sync (Optional)

1. Go to "Settings" → "Network" → "WebDAV"
2. Fill in server address, username, password
3. Enable auto-sync

### ⌨️ Useful Tips

| Action | Description |
|--------|-------------|
| Tap left/right 30% in reader | Turn page |
| Tap center 40% in reader | Show/hide menu |
| Long press comic cover | Quick add to favorites |
| Enter comic ID in search box | Jump directly to the comic |
| Pinch to zoom | Zoom in/out (reader) |
| Swipe back | Go back (Android predictive back gesture) |

---

## 💻 Development Setup

### Prerequisites

1. **Install Flutter SDK**
   ```bash
   # Recommended: use FVM to manage Flutter versions
   dart pub global activate fvm
   fvm install 3.44.0
   fvm use 3.44.0
   ```

2. **Configure Android development environment**
   - Install [Android Studio](https://developer.android.com/studio)
   - Install Android SDK (API Level 21+)
   - Configure `ANDROID_HOME` environment variable

3. **Verify environment**
   ```bash
   flutter doctor
   ```

### Run the Project

```bash
# Get dependencies
flutter pub get

# Start debugging (connect device or start emulator)
flutter run

# Run with specific architecture (faster build)
flutter run --target-platform android-arm64
```

### Debugging Tips

- **View logs**: `flutter logs`
- **Performance profiling**: `flutter run --profile`
- **Hot reload**: Press `r` in the running terminal
- **Hot restart**: Press `R` in the running terminal

### Project Configuration

Some dependencies are referenced via Git. They will be automatically cloned on first `flutter pub get`. If you encounter network issues, configure a proxy:

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 📁 Project Structure

```
KongComic-android/
├── lib/                          # Dart source code
│   ├── components/               # UI component library
│   │   ├── appbar.dart           # Custom AppBar
│   │   ├── button.dart           # Button components
│   │   ├── comic.dart            # Comic card component
│   │   ├── image.dart            # Image component
│   │   ├── navigation_bar.dart   # Bottom navigation bar
│   │   └── ...
│   ├── foundation/               # Foundation layer
│   │   ├── app.dart              # App entry point
│   │   ├── appdata.dart          # App data management
│   │   ├── comic_source/         # Comic source system
│   │   │   ├── comic_source.dart # Comic source base class
│   │   │   ├── models.dart       # Data models
│   │   │   └── parser.dart       # JS parser
│   │   ├── cache_manager.dart    # Cache management
│   │   ├── history.dart          # History records
│   │   └── ...
│   ├── pages/                    # Pages
│   │   ├── main_page.dart        # Main page (tab container)
│   │   ├── reader/               # Reader page
│   │   ├── settings/             # Settings pages
│   │   ├── search_page.dart      # Search page
│   │   └── ...
│   └── utils/                    # Utility classes
│       ├── cbz.dart              # CBZ packaging utility
│       ├── io.dart               # I/O utilities
│       ├── translations.dart     # Internationalization
│       └── ...
├── android/                      # Android platform code
│   ├── app/
│   ├── build.gradle
│   └── ...
├── assets/                       # Asset files
│   ├── translation.json          # Translation file
│   ├── tags.json                 # Tag data
│   └── ...
├── doc/                          # Project documentation
│   ├── comic_source.md           # Comic source dev docs
│   ├── import_comic.md          # Local comic import docs
│   └── js_api.md                # JS API docs
├── pubspec.yaml                  # Flutter project config
└── README.md                    # Project README
```

---

## 🤝 Contributing

Thank you for considering contributing to KongComic!

### 🌟 Ways to Contribute

- 🐛 **Report bugs**: Create an Issue on the [Issues](https://github.com/SkyAlice-source/KongComic-android/issues) page
- 💡 **Suggest features**: Also via Issues, please use the `feature request` label
- 📝 **Improve documentation**: Submit a PR to modify docs in the `doc/` directory
- 🔧 **Submit code**: Fork this repo and submit a Pull Request
- 🌐 **Add comic sources**: Submit comic source scripts to [venera-configs](https://github.com/venera-app/venera-configs)

### 🔄 Code Submission Workflow

#### 1. Fork & Clone

```bash
# After forking, clone your fork
git clone https://github.com/your-username/KongComic-android.git
cd KongComic-android

# Add upstream repository
git remote add upstream https://github.com/SkyAlice-source/KongComic-android.git
```

#### 2. Create Branch

```bash
# Create feature branch from main
git checkout -b feature/your-feature-description
# or
git checkout -b fix/issue-description
```

#### 3. Development Guidelines

**Code Style**:
- Follow the [Dart Style Guide](https://dart.dev/effective-dart/style)
- Use `dart format` to format code
- Use `flutter analyze` to check code quality

**Commit Message Convention** (refer to [Conventional Commits](https://www.conventionalcommits.org/)):

```
feat: add XX feature
fix: fix XX issue
docs: update XX documentation
style: code formatting (no functional changes)
refactor: code refactoring
perf: performance optimization
chore: build/toolchain adjustments
```

#### 4. Testing

```bash
# Run static analysis
flutter analyze

# Run unit tests (if available)
flutter test

# Manual testing of key flows
# - App startup
# - Comic search
# - Reader functionality
# - Download functionality
# - Settings page
```

#### 5. Submit Pull Request

```bash
# Commit your changes
git add .
git commit -m "feat: add XX feature"

# Push to your fork
git push origin feature/your-feature-description
```

Then create a Pull Request on GitHub with:

1. A clear PR description
2. Reference to related Issues (if any)
3. Screenshots (if UI changes are involved)
4. Wait for code review

### 📋 Issue Report Template

**Bug Report**:
```
### Environment
- App Version: v1.1.6
- Device Model: XXX
- Android Version: XXX
- Description: ...

### Steps to Reproduce
1. ...
2. ...

### Expected Behavior
...

### Actual Behavior
...

### Screenshots (Optional)
...
```

### 🔒 Code Review Requirements

- All PRs require at least 1 review approval before merging
- Ensure no missing `mounted` checks (prevents setState-after-dispose)
- Async I/O operations must use async/await, avoid blocking the UI thread
- New dependencies must be justified in `pubspec.yaml`

### 📜 Contributor Agreement

By submitting code, you agree that:
- Your contributions will be published under the GPL-3.0 license
- You have the right to share this code (no third-party IP infringement)

---

## 📄 License

This project is open-sourced under the [GPL-3.0](LICENSE) license.

```
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
```

---

## 🙏 Acknowledgments

- [Venera](https://github.com/venera-app/venera) — Original project by [@wgh136](https://github.com/wgh136)
- [Reasonix](https://reasonix.ai) — AI coding assistant
- [Flutter](https://flutter.dev) — Cross-platform UI framework
- [flutter_qjs](https://github.com/wgh136/flutter_qjs) — JavaScript engine
- All open-source dependency maintainers
- All contributors who submitted Issues and PRs

---

## 📮 Contact

- GitHub Issues: [Report an Issue](https://github.com/SkyAlice-source/KongComic-android/issues)
- Discussions: [Discussions](https://github.com/SkyAlice-source/KongComic-android/discussions) (if enabled)

---

<p align="center">⭐ If this project helps you, please give it a Star!</p>
