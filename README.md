<div align="center">

<img src="https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg/1f9f1.svg" width="80" alt="grass block"/>

# Minecraft Launcher

**Fast · Lightweight · Offline-capable · Fabric-ready**

[![Made by Bugrahan](https://img.shields.io/badge/made%20by-bugrahan-5da53f?style=for-the-badge&logo=minecraft&logoColor=white)](https://tiktok.com/@script.xd)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]()
[![Go](https://img.shields.io/badge/Go-1.23-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://go.dev)
[![License](https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge)]()

[![TikTok](https://img.shields.io/badge/TikTok-script.xd-000000?style=flat-square&logo=tiktok&logoColor=white)](https://tiktok.com/@script.xd)
[![Discord](https://img.shields.io/badge/Discord-bdugrahan-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.com/users/bdugrahan)
[![Instagram](https://img.shields.io/badge/Instagram-bu9r44-E4405F?style=flat-square&logo=instagram&logoColor=white)](https://instagram.com/bu9r44)

</div>

---

## 📖 Table of Contents

- [Features](#-features)
- [System Requirements](#-system-requirements)
- [Build Requirements](#-build-requirements)
- [Compiled Output](#-compiled-output)
- [Runtime Downloads](#-runtime-downloads)
- [Total Disk Footprint](#-total-disk-footprint)
- [Network Usage](#-network-usage)
- [What It Does NOT Require](#-what-it-does-not-require)
- [Supported Minecraft Versions](#-supported-minecraft-versions)
- [Build](#-build)
- [Project Layout](#-project-layout)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

---

## ✨ Features

| | |
|---|---|
| 🌑 **Modern dark UI** | Native WebView2 window with HTML/CSS interface |
| 🔍 **Searchable versions** | Filter all release and snapshot versions instantly |
| 🧵 **Fabric auto-install** | Auto-detects Fabric support; falls back to Vanilla |
| ☕ **Auto Java** | Downloads the correct JRE per Minecraft version |
| ⚡ **Parallel downloads** | 32 concurrent connections with SHA1 verification |
| 🛡️ **Self-healing** | Corrupt-file detection with automatic re-download and retry |
| 💾 **Persistent settings** | Username, RAM, and version saved to `settings.json` |
| 🔒 **Offline mode** | No Mojang account required |
| 🕵️ **No telemetry** | Zero background services, zero tracking |
| 📦 **One-click build** | `build.bat` auto-installs Go and MinGW if missing |

---

## 💻 System Requirements

| Requirement | Minimum | Recommended | Notes |
|---|---|---|---|
| **OS** | Windows 10 1809 (x64) | Windows 11 (x64) | WebView2 needs Win10 1809 or newer |
| **CPU** | Dual-core 2.0 GHz | Quad-core 3.0 GHz or better | Launcher is light; game runs on Java |
| **System RAM** | 4 GB | 8 GB or more | Launcher ~150 MB; game 2–4 GB |
| **Free disk** | 1.5 GB | 3 GB or more | Build plus first game install |
| **GPU** | OpenGL 3.2 | OpenGL 4.5 | Game requirement, not launcher |
| **Internet** | Required for first launch | Broadband 10 Mbps+ | Downloads Java, game files, assets |
| **WebView2 Runtime** | Required | Preinstalled on Win10 21H2+ / Win11 | If missing, install Evergreen Bootstrapper from Microsoft |

---

## 🛠️ Build Requirements

`build.bat` auto-detects and downloads missing tools into the `mclauncher` folder. No manual installs needed. Listed here for transparency.

| Package | Auto-downloaded | Size | Source |
|---|---|:---:|---|
| Go 1.23.4 (portable) | ✅ if `go` not in PATH | **~78 MB** | [go.dev/dl](https://go.dev/dl/) |
| MinGW-w64 (gcc and g++) | ✅ if `gcc`/`g++` not in PATH | **~130 MB** | winlibs via GitHub API |
| Go modules (`webview_go`, `go-winres`) | ✅ always | **~15 MB** | proxy.golang.org |
| **Total build download** | | **~223 MB** | |

> Tools are stored in `mclauncher/go/` and `mclauncher/mingw/` and reused on future builds.

---

## 📦 Compiled Output

| Artifact | Size |
|---|---|
| `MinecraftLauncher.exe` | **~8–12 MB** |
| **Includes** | Icon, Common Controls v6 manifest, embedded HTML UI, all Go code |
| **External DLLs** | None (WebView2 loads from system) |

---

## 📥 Runtime Downloads

First `PLAY` click per Minecraft version.

| Component | Size | Source | Cached in |
|---|---|---|---|
| Java JRE (per major, e.g. 21) | **~45–50 MB** | Adoptium API | `mclauncher/jre/<major>/` |
| Minecraft `client.jar` | **~25–35 MB** | Mojang CDN | `mclauncher/versions/<id>/` |
| Libraries (LWJGL, Fabric, etc.) | **~35–55 MB** | Mojang & Fabric Maven | `mclauncher/libraries/` |
| Assets (sounds, textures, lang) | **~150–300 MB** | Mojang resources CDN | `mclauncher/assets/objects/` |
| Natives (DLLs) | **~5–10 MB** | Mojang CDN | `mclauncher/natives/` |
| **Total per version (first install)** | **~260–450 MB** | | |

> Java JRE and libraries are **shared across versions**. Installing a second version of the same major only adds the client jar and its own assets (~50–150 MB).

---

## 💾 Total Disk Footprint

After the first full install.

| Phase | Size |
|---|---|
| Launcher folder and build tools (`go/`, `mingw/`) | **~215 MB** |
| `MinecraftLauncher.exe` | **~10 MB** |
| Java JRE (one major) | **~50 MB** |
| Game files (one version) | **~250–400 MB** |
| **Total after first play** | **~525–675 MB** |

> Each additional Minecraft version adds **50–150 MB** (reuses JRE and libraries when the Java major matches).

---

## 🌐 Network Usage

| Phase | Data |
|---|---|
| Build (first run) | **~223 MB** download |
| First game install (per version) | **~260–450 MB** download |
| Subsequent launches | **~0 MB** (only version manifest, ~200 KB) |
| Playing (offline mode) | **0 MB** — no auth, no telemetry |

---

## 🚫 What It Does NOT Require

- ❌ No Python, Node.js, .NET SDK, or preinstalled Java
- ❌ No Minecraft or Mojang account (offline mode, `accessToken` is `null`)
- ❌ No administrator rights (everything extracts to its own folder)
- ❌ No background services, no telemetry, no auto-updater
- ❌ No external DLLs to ship (WebView2 comes from the system)

---

## 🎮 Supported Minecraft Versions

- ✅ **All** release and snapshot versions from Mojang `version_manifest_v2.json`
- ✅ **Fabric** auto-applied when available via `meta.fabricmc.net`
- ✅ **Vanilla** fallback when Fabric does not support the version yet (e.g. brand new releases like 26.2)
- ⚠️ **Forge** not currently supported (planned)

---

## 🧱 Build

1. Save `build.bat` to any folder.
2. Double-click it. It will:
   - Detect or download **Go** and **MinGW**
   - Extract the Go source and generate the icon
   - Build `MinecraftLauncher.exe` in the `mclauncher` folder
3. Run `mclauncher/MinecraftLauncher.exe`.

The bat prints step markers `[1]` through `[7]`. On error it prints an English message and exits.

---

## 📁 Project Layout
