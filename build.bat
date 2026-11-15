@echo off
setlocal enabledelayedexpansion
set "D=%~dp0mclauncher"
set "W=%~dp0_build"
if not exist "%D%" mkdir "%D%"
if not exist "%W%" mkdir "%W%"
copy /Y "%~f0" "%W%\self.bat" >nul

echo [1]
if exist "%D%\go\bin\go.exe" set "PATH=%D%\go\bin;!PATH!"
if exist "%D%\mingw" for /d %%X in ("%D%\mingw\*") do set "PATH=%%X\bin;!PATH!"

echo [2]
where go >nul 2>nul
if errorlevel 1 (
    curl -sSL --retry 3 -o "%W%\go.zip" "https://go.dev/dl/go1.23.4.windows-amd64.zip"
    if errorlevel 1 (echo go download failed & exit /b 1)
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%W%\go.zip' -DestinationPath '%D%' -Force"
    if errorlevel 1 (echo go extract failed & exit /b 1)
    set "PATH=%D%\go\bin;!PATH!"
)

echo [3]
where gcc >nul 2>nul
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 3;$i++){try{$r=Invoke-RestMethod 'https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest';$a=($r.assets|Where-Object{$_.name -like '*x86_64*posix*seh*.zip' -and $_.name -notlike '*llvm*'}|Select-Object -First 1);if($a){Write-Output $a.browser_download_url;break}}catch{Start-Sleep 2}}" > "%W%\u.txt"
    set /p U=<"%W%\u.txt"
    if "!U!"=="" (echo mingw url failed & exit /b 1)
    curl -sSL --retry 3 -o "%W%\mw.zip" "!U!"
    if errorlevel 1 (echo mingw download failed & exit /b 1)
    if not exist "%D%\mingw" mkdir "%D%\mingw"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%W%\mw.zip' -DestinationPath '%D%\mingw' -Force"
    if errorlevel 1 (echo mingw extract failed & exit /b 1)
    for /d %%X in ("%D%\mingw\*") do set "PATH=%%X\bin;!PATH!"
)
where g++ >nul 2>nul
if errorlevel 1 (echo g++ missing & exit /b 1)

echo [4]
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%W%\self.bat',[Text.Encoding]::UTF8);$m='#'+'##GO'+'###';$g=$t.IndexOf($m);$e=New-Object Text.UTF8Encoding $false;$s=$t.Substring($g+$m.Length).Trim();if(-not $s.StartsWith('package main')){exit 1};[IO.File]::WriteAllText('%D%\main.go',$s,$e)"
if errorlevel 1 (echo extract failed & exit /b 1)

echo [5]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Drawing;$b=New-Object System.Drawing.Bitmap 64,64;$g=[System.Drawing.Graphics]::FromImage($b);$g.Clear([System.Drawing.Color]::FromArgb(93,165,63));$br=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(139,94,60));$g.FillRectangle($br,0,32,64,32);$d=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70,125,47));$g.FillRectangle($d,0,0,64,4);$g.FillRectangle($d,0,0,4,32);$g.Dispose();$b.Save('%D%\logo.png',[System.Drawing.Imaging.ImageFormat]::Png);$b.Dispose()"

cd /d "%D%"
if not exist go.mod go mod init mclauncher >nul 2>nul

echo [6]
go run github.com/tc-hib/go-winres@latest simply --icon logo.png --manifest gui --product-name "Minecraft Launcher" --file-version 1.0.0.0 --product-version 1.0.0.0
if errorlevel 1 (echo winres failed & exit /b 1)
set N=0
:ml
set /a N+=1
go get github.com/webview/webview_go
go mod tidy
if not errorlevel 1 goto mo
if %N% LSS 3 (timeout /t 3 /nobreak >nul & goto ml)
echo dependency failed
exit /b 1
:mo

echo [7]
set CGO_ENABLED=1
go build -ldflags "-s -w -H windowsgui" -o MinecraftLauncher.exe .
if errorlevel 1 (echo build failed & exit /b 1)

del "%W%\self.bat" >nul 2>nul
exit /b 0

###GO###
package main

import (
	"archive/zip"
	"crypto/md5"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	webview "github.com/webview/webview_go"
)

const versionManifestURL = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

var (
	baseDir, gameDir, assetsDir, librariesDir, versionsDir, nativesDir, settingsPath string
)

type Settings struct {
	Username string `json:"username"`
	RAM      int    `json:"ram_mb"`
	Version  string `json:"version"`
}

type VersionManifest struct {
	Versions []versionItem `json:"versions"`
}

type versionItem struct {
	ID   string `json:"id"`
	Type string `json:"type"`
	URL  string `json:"url"`
}

type Library struct {
	Name      string `json:"name"`
	URL       string `json:"url"`
	Downloads struct {
		Artifact struct {
			Path string `json:"path"`
			URL  string `json:"url"`
			SHA1 string `json:"sha1"`
		} `json:"artifact"`
		Classifiers map[string]struct {
			Path string `json:"path"`
			URL  string `json:"url"`
			SHA1 string `json:"sha1"`
		} `json:"classifiers"`
	} `json:"downloads"`
	Natives map[string]string `json:"natives"`
}

type VersionMeta struct {
	ID        string `json:"id"`
	MainClass string `json:"mainClass"`
	JavaVersion struct {
		MajorVersion int `json:"majorVersion"`
	} `json:"javaVersion"`
	AssetIndex struct {
		ID   string `json:"id"`
		URL  string `json:"url"`
		SHA1 string `json:"sha1"`
	} `json:"assetIndex"`
	Downloads struct {
		Client struct {
			URL  string `json:"url"`
			SHA1 string `json:"sha1"`
		} `json:"client"`
	} `json:"downloads"`
	Libraries []Library `json:"libraries"`
}

type task struct{ URL, Dest, SHA1 string }

type PlayOpts struct {
	Username string `json:"username"`
	RAM      int    `json:"ram_mb"`
	Version  string `json:"version"`
	URL      string `json:"url"`
}

var currentWV webview.WebView

func logln(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	f, err := os.OpenFile(filepath.Join(baseDir, "launcher.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err == nil {
		fmt.Fprintf(f, "[%s] %s\n", time.Now().Format("15:04:05"), msg)
		f.Close()
	}
}

func jsProgress(status string, done, total int) {
	if currentWV == nil {
		return
	}
	currentWV.Dispatch(func() {
		currentWV.Eval(fmt.Sprintf("window.onProgress && window.onProgress(%q, %d, %d)", status, done, total))
	})
}

func fetchJSON(url string, out any) error {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("%d %s", resp.StatusCode, url)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func sha1File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha1.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func downloadOnce(url, dest string) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
		return err
	}
	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("%d %s", resp.StatusCode, url)
	}
	tmp := dest + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	f.Close()
	return os.Rename(tmp, dest)
}

func download(url, dest, sum string) error {
	const maxAttempts = 4
	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if sum != "" {
			if got, err := sha1File(dest); err == nil && got == sum {
				return nil
			}
		}
		err := downloadOnce(url, dest)
		if err == nil {
			if sum == "" {
				return nil
			}
			if got, verr := sha1File(dest); verr == nil && got == sum {
				return nil
			}
			os.Remove(dest)
			lastErr = fmt.Errorf("sha1 mismatch: %s", filepath.Base(dest))
		} else {
			os.Remove(dest + ".part")
			lastErr = err
		}
		if attempt < maxAttempts {
			time.Sleep(time.Duration(attempt) * 500 * time.Millisecond)
		}
	}
	return fmt.Errorf("%d attempts failed: %w", maxAttempts, lastErr)
}

func parallelDownload(tasks []task, onProgress func(done, total int)) {
	sem := make(chan struct{}, 32)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var failed []task
	done, total := 0, len(tasks)
	for _, t := range tasks {
		wg.Add(1)
		go func(t task) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if err := download(t.URL, t.Dest, t.SHA1); err != nil {
				mu.Lock()
				failed = append(failed, t)
				mu.Unlock()
				logln("download fail: %s: %v", filepath.Base(t.Dest), err)
			}
			mu.Lock()
			done++
			d := done
			mu.Unlock()
			if onProgress != nil {
				onProgress(d, total)
			}
		}(t)
	}
	wg.Wait()
	if len(failed) > 0 {
		for i, t := range failed {
			download(t.URL, t.Dest, t.SHA1)
			if onProgress != nil {
				onProgress(total-len(failed)+i+1, total)
			}
		}
	}
}

func unzipFlat(src, dest string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer r.Close()
	for _, f := range r.File {
		if strings.HasSuffix(f.Name, "/") || strings.Contains(f.Name, "..") {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		w, err := os.Create(filepath.Join(dest, filepath.Base(f.Name)))
		if err != nil {
			rc.Close()
			return err
		}
		io.Copy(w, rc)
		w.Close()
		rc.Close()
	}
	return nil
}

func unzipFull(src, dest string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer r.Close()
	cleanDest := filepath.Clean(dest)
	for _, f := range r.File {
		p := filepath.Join(dest, filepath.Clean(f.Name))
		if !strings.HasPrefix(p, cleanDest+string(os.PathSeparator)) && p != cleanDest {
			continue
		}
		if f.FileInfo().IsDir() {
			os.MkdirAll(p, 0755)
			continue
		}
		os.MkdirAll(filepath.Dir(p), 0755)
		rc, err := f.Open()
		if err != nil {
			return err
		}
		w, err := os.Create(p)
		if err != nil {
			rc.Close()
			return err
		}
		io.Copy(w, rc)
		w.Close()
		rc.Close()
	}
	return nil
}

func resolveLib(lib Library) (url, path, sha1sum string) {
	if lib.Downloads.Artifact.URL != "" {
		return lib.Downloads.Artifact.URL, lib.Downloads.Artifact.Path, lib.Downloads.Artifact.SHA1
	}
	parts := strings.Split(lib.Name, ":")
	if len(parts) < 3 {
		return "", "", ""
	}
	group, artifact, version := parts[0], parts[1], parts[2]
	base := lib.URL
	if base == "" {
		base = "https://maven.fabricmc.net/"
	}
	if !strings.HasSuffix(base, "/") {
		base += "/"
	}
	rel := strings.ReplaceAll(group, ".", "/") + "/" + artifact + "/" + version + "/" + artifact + "-" + version + ".jar"
	return base + rel, rel, ""
}

func offlineUUID(username string) string {
	h := md5.Sum([]byte("OfflinePlayer:" + username))
	h[6] = (h[6] & 0x0f) | 0x30
	h[8] = (h[8] & 0x3f) | 0x80
	x := hex.EncodeToString(h[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s", x[0:8], x[8:12], x[12:16], x[16:20], x[20:])
}

func getVanillaMeta(versionURL string) (*VersionMeta, error) {
	var meta VersionMeta
	if err := fetchJSON(versionURL, &meta); err != nil {
		return nil, err
	}
	return &meta, nil
}

func getFabricMerged(versionID, versionURL string) (*VersionMeta, error) {
	vanilla, err := getVanillaMeta(versionURL)
	if err != nil {
		return nil, err
	}
	var loaders []struct {
		Version string `json:"version"`
	}
	if err := fetchJSON(fmt.Sprintf("https://meta.fabricmc.net/v2/versions/loader/%s", versionID), &loaders); err != nil {
		return nil, fmt.Errorf("fabric loader: %w", err)
	}
	if len(loaders) == 0 {
		return nil, fmt.Errorf("fabric not supported: %s", versionID)
	}
	loader := loaders[0].Version
	if loader == "" {
		return nil, fmt.Errorf("fabric loader empty")
	}
	var fabric VersionMeta
	if err := fetchJSON(fmt.Sprintf("https://meta.fabricmc.net/v2/versions/loader/%s/%s/profile/json", versionID, loader), &fabric); err != nil {
		return nil, fmt.Errorf("fabric profile: %w", err)
	}
	merged := *vanilla
	merged.MainClass = fabric.MainClass
	merged.Libraries = append(merged.Libraries, fabric.Libraries...)
	merged.ID = fabric.ID
	return &merged, nil
}

func ensureJava(major int) (string, error) {
	if major <= 0 {
		major = 21
	}
	dir := filepath.Join(baseDir, "jre", strconv.Itoa(major))
	exe := filepath.Join(dir, "bin", "java.exe")
	if _, err := os.Stat(exe); err == nil {
		return exe, nil
	}
	logln("downloading java %d...", major)
	os.MkdirAll(dir, 0755)
	zipPath := filepath.Join(baseDir, "jre", fmt.Sprintf("jre-%d.zip", major))
	url := fmt.Sprintf("https://api.adoptium.net/v3/binary/latest/%d/ga/windows/x64/jre/hotspot/normal/eclipse", major)
	if err := download(url, zipPath, ""); err != nil {
		return "", fmt.Errorf("jre %d download: %w", major, err)
	}
	tmp := dir + "_tmp"
	os.RemoveAll(tmp)
	if err := unzipFull(zipPath, tmp); err != nil {
		os.Remove(zipPath)
		return "", fmt.Errorf("jre %d extract: %w", major, err)
	}
	os.Remove(zipPath)
	entries, _ := os.ReadDir(tmp)
	var src string
	for _, e := range entries {
		if e.IsDir() && strings.HasPrefix(strings.ToLower(e.Name()), "jdk") {
			src = filepath.Join(tmp, e.Name())
			break
		}
	}
	if src == "" {
		src = tmp
	}
	subEntries, _ := os.ReadDir(src)
	for _, e := range subEntries {
		target := filepath.Join(dir, e.Name())
		os.RemoveAll(target)
		os.Rename(filepath.Join(src, e.Name()), target)
	}
	os.RemoveAll(tmp)
	if _, err := os.Stat(exe); err != nil {
		return "", fmt.Errorf("jre %d java missing after install", major)
	}
	return exe, nil
}

func extractNatives(libs []Library) {
	os.MkdirAll(nativesDir, 0755)
	for _, lib := range libs {
		if lib.Natives == nil {
			continue
		}
		var key string
		switch runtime.GOOS {
		case "windows":
			key = "windows"
		case "linux":
			key = "linux"
		case "darwin":
			key = "osx"
		}
		classifier, ok := lib.Natives[key]
		if !ok {
			continue
		}
		art, ok := lib.Downloads.Classifiers[classifier]
		if !ok {
			continue
		}
		zp := filepath.Join(librariesDir, art.Path)
		if err := download(art.URL, zp, art.SHA1); err == nil {
			unzipFlat(zp, nativesDir)
		}
	}
}

func installAndLaunch(versionID, versionURL, username string, ramMB int) error {
	jsProgress("Fetching Fabric profile...", 0, 0)
	meta, err := getFabricMerged(versionID, versionURL)
	loader := "Fabric"
	if err != nil {
		logln("fabric unavailable, vanilla: %v", err)
		jsProgress("Fabric unavailable, using Vanilla...", 0, 0)
		meta, err = getVanillaMeta(versionURL)
		loader = "Vanilla"
		if err != nil {
			return err
		}
	}

	major := meta.JavaVersion.MajorVersion
	if major <= 0 {
		major = 21
	}
	jsProgress(fmt.Sprintf("Preparing Java %d...", major), 0, 0)
	javaExe, err := ensureJava(major)
	if err != nil {
		return err
	}

	vdir := filepath.Join(versionsDir, meta.ID)
	os.MkdirAll(vdir, 0755)

	jsProgress("Preparing libraries...", 0, 0)
	var tasks []task
	tasks = append(tasks, task{meta.Downloads.Client.URL, filepath.Join(vdir, versionID+".jar"), meta.Downloads.Client.SHA1})
	for _, lib := range meta.Libraries {
		u, p, s := resolveLib(lib)
		if u == "" {
			continue
		}
		tasks = append(tasks, task{u, filepath.Join(librariesDir, p), s})
	}
	indexPath := filepath.Join(assetsDir, "indexes", meta.AssetIndex.ID+".json")
	tasks = append(tasks, task{meta.AssetIndex.URL, indexPath, meta.AssetIndex.SHA1})
	jsProgress(fmt.Sprintf("Downloading %d files...", len(tasks)), 0, len(tasks))
	parallelDownload(tasks, func(d, t int) { jsProgress("Downloading files", d, t) })

	jsProgress("Reading asset index...", 0, 0)
	var index struct {
		Objects map[string]struct {
			Hash string `json:"hash"`
		} `json:"objects"`
	}
	raw, err := os.ReadFile(indexPath)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(raw, &index); err != nil {
		return err
	}
	var assetTasks []task
	for _, obj := range index.Objects {
		p := obj.Hash[:2]
		assetTasks = append(assetTasks, task{
			fmt.Sprintf("https://resources.download.minecraft.net/%s/%s", p, obj.Hash),
			filepath.Join(assetsDir, "objects", p, obj.Hash),
			obj.Hash,
		})
	}
	jsProgress(fmt.Sprintf("Downloading %d assets...", len(assetTasks)), 0, len(assetTasks))
	parallelDownload(assetTasks, func(d, t int) { jsProgress("Downloading assets", d, t) })

	jsProgress("Extracting natives...", 0, 0)
	extractNatives(meta.Libraries)

	sep := ":"
	if runtime.GOOS == "windows" {
		sep = ";"
	}
	var cp []string
	for _, lib := range meta.Libraries {
		_, p, _ := resolveLib(lib)
		if p == "" {
			continue
		}
		cp = append(cp, filepath.Join(librariesDir, p))
	}
	cp = append(cp, filepath.Join(vdir, versionID+".jar"))
	uuid := offlineUUID(username)
	args := []string{
		fmt.Sprintf("-Xmx%dM", ramMB), "-Xms512M",
		"-Djava.library.path=" + nativesDir,
		"-Dminecraft.launcher.brand=minecraft-launcher",
		"-cp", strings.Join(cp, sep),
		meta.MainClass,
		"--username", username,
		"--uuid", uuid,
		"--accessToken", "null",
		"--clientId", "",
		"--xuid", "",
		"--userType", "legacy",
		"--version", meta.ID,
		"--versionType", "release",
		"--gameDir", gameDir,
		"--assetsDir", assetsDir,
		"--assetIndex", meta.AssetIndex.ID,
	}
	jsProgress("Launching game ("+loader+")...", 0, 0)
	logln("java: %s | loader: %s", javaExe, loader)
	cmd := exec.Command(javaExe, args...)
	cmd.Dir = gameDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Start()
}

func loadSettings() *Settings {
	s := &Settings{Username: "Player", RAM: 4096, Version: ""}
	if data, err := os.ReadFile(settingsPath); err == nil {
		json.Unmarshal(data, s)
	}
	return s
}

func saveSettings(s *Settings) {
	data, _ := json.MarshalIndent(s, "", "  ")
	os.WriteFile(settingsPath, data, 0644)
}

const indexHTML = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Minecraft Launcher</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#0a0a0f;--panel:#14141c;--panel2:#1c1c26;--border:#2a2a3a;--text:#e8e8f0;--muted:#7a7a90;--accent:#5da53f;--accent-h:#6cbb4a;--danger:#e05555}
html,body{height:100%}
body{font-family:'Segoe UI Variable','Segoe UI',system-ui,sans-serif;background:radial-gradient(circle at 20% 0%,#151522 0%,var(--bg) 60%);color:var(--text);padding:20px;display:flex;align-items:flex-start;justify-content:center;overflow:hidden;user-select:none}
.app{width:100%;max-width:780px;height:calc(100vh - 40px);display:flex;flex-direction:column;gap:14px}
.header{display:flex;align-items:center;gap:14px;padding:4px 0}
.block{width:38px;height:38px;border-radius:6px;background:linear-gradient(to bottom,var(--accent) 0%,var(--accent) 50%,#8b5e3c 50%,#8b5e3c 100%);box-shadow:0 4px 16px rgba(93,165,63,.25),inset 0 0 0 1px rgba(0,0,0,.3);animation:float 3s ease-in-out infinite}
@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-3px)}}
.title{font-size:20px;font-weight:800;letter-spacing:3px;color:var(--accent)}
.credit{color:var(--muted);font-size:11px;letter-spacing:1px;margin-left:auto}
.credit b{color:var(--accent);font-weight:700}
.card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:16px}
.row{display:flex;gap:10px;margin-bottom:12px}
label{display:block;font-size:11px;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:1px;font-weight:600}
input{width:100%;padding:10px 12px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:13px;outline:none;transition:border .15s,box-shadow .15s;font-family:inherit}
input:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(93,165,63,.15)}
.col{flex:1}
.search-wrap{position:relative}
.search-wrap input{padding-left:34px}
.search-wrap::before{content:'⌕';position:absolute;left:12px;top:50%;transform:translateY(-50%);color:var(--muted);font-size:16px;pointer-events:none}
.version-list{max-height:230px;overflow-y:auto;background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:4px;margin-top:8px}
.version-list::-webkit-scrollbar{width:8px}
.version-list::-webkit-scrollbar-thumb{background:var(--border);border-radius:4px}
.v-item{padding:9px 12px;border-radius:6px;cursor:pointer;display:flex;justify-content:space-between;align-items:center;font-size:13px;transition:background .1s}
.v-item:hover{background:var(--panel2)}
.v-item.sel{background:rgba(93,165,63,.15);border-left:2px solid var(--accent);padding-left:10px}
.v-item .id{font-weight:600;font-family:'JetBrains Mono',Consolas,monospace}
.v-item .type{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:1px;padding:2px 6px;border-radius:4px;background:var(--panel2)}
.v-item .type.release{color:var(--accent)}
.range-row{display:flex;align-items:center;gap:12px}
input[type=range]{flex:1;padding:0;background:transparent;border:none;-webkit-appearance:none;height:6px;background:var(--panel2);border-radius:3px;outline:none}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:16px;height:16px;background:var(--accent);border-radius:50%;cursor:pointer;box-shadow:0 2px 6px rgba(0,0,0,.4)}
.ram-val{min-width:80px;text-align:right;color:var(--accent);font-weight:700;font-size:13px;font-family:'JetBrains Mono',Consolas,monospace}
button{width:100%;padding:13px;background:var(--accent);color:#fff;border:none;border-radius:10px;font-size:14px;font-weight:700;letter-spacing:1.5px;cursor:pointer;transition:background .15s,transform .1s;font-family:inherit;text-transform:uppercase}
button:hover:not(:disabled){background:var(--accent-h)}
button:active:not(:disabled){transform:scale(.99)}
button:disabled{background:var(--panel2);color:var(--muted);cursor:not-allowed}
.progress{margin-top:12px;display:none}
.progress.show{display:block}
.bar{height:6px;background:var(--bg);border-radius:3px;overflow:hidden;border:1px solid var(--border)}
.bar-fill{height:100%;background:linear-gradient(90deg,var(--accent),var(--accent-h));width:0%;transition:width .2s}
.status{margin-top:8px;font-size:12px;color:var(--muted);text-align:center;min-height:16px;font-family:'JetBrains Mono',Consolas,monospace}
.status.err{color:var(--danger)}
.footer{display:flex;justify-content:center;gap:14px;margin-top:auto;padding-top:10px}
.social{display:flex;align-items:center;justify-content:center;width:36px;height:36px;border-radius:10px;background:var(--panel);border:1px solid var(--border);color:var(--muted);text-decoration:none;transition:all .2s;position:relative;overflow:hidden}
.social:hover{color:var(--accent);border-color:var(--accent);transform:translateY(-2px);box-shadow:0 6px 18px rgba(93,165,63,.3)}
.social svg{width:18px;height:18px;fill:currentColor;transition:transform .2s}
.social:hover svg{transform:scale(1.15)}
.social::after{content:attr(data-label);position:absolute;bottom:-24px;left:50%;transform:translateX(-50%);font-size:10px;color:var(--muted);white-space:nowrap;opacity:0;transition:opacity .2s}
.social:hover::after{opacity:1}
</style></head><body>
<div class="app">
  <div class="header">
    <div class="block"></div>
    <div class="title">MINECRAFT</div>
    <div class="credit">made by <b>bugrahan</b></div>
  </div>
  <div class="card">
    <div class="row">
      <div class="col">
        <label>Username</label>
        <input id="username" placeholder="player name" maxlength="16" autocomplete="off">
      </div>
      <div class="col" style="max-width:200px">
        <label>RAM</label>
        <div class="range-row">
          <input id="ram" type="range" min="1024" max="16384" step="256" value="4096">
          <span class="ram-val" id="ramVal">4096 MB</span>
        </div>
      </div>
    </div>
    <label>Search Version</label>
    <div class="search-wrap"><input id="search" placeholder="search versions: 1.21, 26.2, ..." autocomplete="off"></div>
    <div class="version-list" id="list"></div>
  </div>
  <button id="play" disabled>PLAY</button>
  <div class="progress" id="progress">
    <div class="bar"><div class="bar-fill" id="fill"></div></div>
    <div class="status" id="status"></div>
  </div>
  <div class="footer">
    <a class="social" data-label="script.xd" href="https://tiktok.com/@script.xd" target="_blank" rel="noopener">
      <svg viewBox="0 0 24 24"><path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.2 1.74 2.89 2.89 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.13V9.4a6.84 6.84 0 0 0-1-.05A6.33 6.33 0 0 0 5 20.1a6.34 6.34 0 0 0 10.86-4.43v-7a8.16 8.16 0 0 0 4.77 1.52v-3.4a4.85 4.85 0 0 1-1-.1z"/></svg>
    </a>
    <a class="social" data-label="bdugrahan" href="https://discord.com/users/bdugrahan" target="_blank" rel="noopener">
      <svg viewBox="0 0 24 24"><path d="M20.32 4.37a19.79 19.79 0 0 0-4.89-1.52.07.07 0 0 0-.08.04c-.21.38-.44.87-.6 1.25a18.27 18.27 0 0 0-5.5 0 12.64 12.64 0 0 0-.61-1.25.08.08 0 0 0-.08-.04 19.74 19.74 0 0 0-4.88 1.52.07.07 0 0 0-.03.03C.53 9.05-.32 13.58.1 18.06a.08.08 0 0 0 .03.05 19.9 19.9 0 0 0 5.99 3.03.08.08 0 0 0 .08-.03c.46-.63.87-1.29 1.22-1.99a.08.08 0 0 0-.04-.11 13.1 13.1 0 0 1-1.87-.89.08.08 0 0 1-.01-.13c.13-.09.25-.19.37-.29a.07.07 0 0 1 .08-.01 14.2 14.2 0 0 0 12.06 0 .07.07 0 0 1 .08.01c.12.1.24.2.37.29a.08.08 0 0 1-.01.13c-.6.35-1.22.64-1.87.89a.08.08 0 0 0-.04.11c.36.7.77 1.36 1.22 1.99a.08.08 0 0 0 .08.03 19.84 19.84 0 0 0 6-3.03.08.08 0 0 0 .03-.05c.5-5.18-.84-9.68-3.55-13.66a.06.06 0 0 0-.03-.03zM8.02 15.33c-1.18 0-2.16-1.08-2.16-2.42 0-1.33.96-2.42 2.16-2.42 1.21 0 2.18 1.1 2.16 2.42 0 1.34-.96 2.42-2.16 2.42zm7.97 0c-1.18 0-2.16-1.08-2.16-2.42 0-1.33.95-2.42 2.16-2.42 1.21 0 2.18 1.1 2.16 2.42 0 1.34-.95 2.42-2.16 2.42z"/></svg>
    </a>
    <a class="social" data-label="bu9r44" href="https://instagram.com/bu9r44" target="_blank" rel="noopener">
      <svg viewBox="0 0 24 24"><path d="M12 2.16c3.2 0 3.58.01 4.85.07 1.17.05 1.8.25 2.23.41.56.22.96.48 1.38.9.42.42.68.82.9 1.38.16.42.36 1.06.41 2.23.06 1.27.07 1.65.07 4.85s-.01 3.58-.07 4.85c-.05 1.17-.25 1.8-.41 2.23-.22.56-.48.96-.9 1.38-.42.42-.82.68-1.38.9-.42.16-1.06.36-2.23.41-1.27.06-1.65.07-4.85.07s-3.58-.01-4.85-.07c-1.17-.05-1.8-.25-2.23-.41a3.72 3.72 0 0 1-1.38-.9 3.72 3.72 0 0 1-.9-1.38c-.16-.42-.36-1.06-.41-2.23C2.17 15.58 2.16 15.2 2.16 12s.01-3.58.07-4.85c.05-1.17.25-1.8.41-2.23.22-.56.48-.96.9-1.38.42-.42.82-.68 1.38-.9.42-.16 1.06-.36 2.23-.41C8.42 2.17 8.8 2.16 12 2.16zM12 0C8.74 0 8.33.01 7.05.07 5.78.13 4.9.33 4.14.63c-.79.31-1.46.72-2.13 1.38A5.88 5.88 0 0 0 .63 4.14C.33 4.9.13 5.78.07 7.05.01 8.33 0 8.74 0 12s.01 3.67.07 4.95c.06 1.27.26 2.15.56 2.91.31.79.72 1.46 1.38 2.13a5.88 5.88 0 0 0 2.13 1.38c.76.3 1.64.5 2.91.56C8.33 23.99 8.74 24 12 24s3.67-.01 4.95-.07c1.27-.06 2.15-.26 2.91-.56a5.88 5.88 0 0 0 2.13-1.38 5.88 5.88 0 0 0 1.38-2.13c.3-.76.5-1.64.56-2.91.06-1.28.07-1.69.07-4.95s-.01-3.67-.07-4.95c-.06-1.27-.26-2.15-.56-2.91a5.88 5.88 0 0 0-1.38-2.13A5.88 5.88 0 0 0 19.86.63c-.76-.3-1.64-.5-2.91-.56C15.67.01 15.26 0 12 0zm0 5.84a6.16 6.16 0 1 0 0 12.32 6.16 6.16 0 0 0 0-12.32zM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.4-11.85a1.44 1.44 0 1 0 0 2.88 1.44 1.44 0 0 0 0-2.88z"/></svg>
    </a>
  </div>
</div>
<script>
let versions=[], selected=null, polling=false;
const $=id=>document.getElementById(id);

async function init(){
  const [v,s]=await Promise.all([window.getVersions(),window.getSettings()]);
  versions=JSON.parse(v);
  if(s.username)$('username').value=s.username;
  if(s.ram_mb){$('ram').value=s.ram_mb;$('ramVal').textContent=s.ram_mb+' MB';}
  selected=s.version?versions.find(x=>x.id===s.version):null;
  render();
  if(selected)$('play').disabled=false;
}

function render(){
  const q=$('search').value.toLowerCase().trim();
  const list=$('list');
  list.innerHTML='';
  const filtered=versions.filter(v=>!q||v.id.toLowerCase().includes(q));
  if(filtered.length===0){list.innerHTML='<div style="padding:20px;text-align:center;color:var(--muted);font-size:12px">no results</div>';return;}
  for(const v of filtered){
    const d=document.createElement('div');
    d.className='v-item'+(selected&&selected.id===v.id?' sel':'');
    d.innerHTML='<span class="id">'+v.id+'</span><span class="type '+v.type+'">'+v.type+'</span>';
    d.onclick=()=>{selected=v;render();$('play').disabled=false;};
    list.appendChild(d);
  }
}
$('search').addEventListener('input',render);
$('ram').addEventListener('input',e=>{$('ramVal').textContent=e.target.value+' MB';});

$('play').addEventListener('click',async()=>{
  const username=$('username').value.trim();
  if(!username){showStatus('username is empty',true);return;}
  if(!selected){showStatus('select a version',true);return;}
  const ram=parseInt($('ram').value);
  $('play').disabled=true;
  $('progress').classList.add('show');
  showStatus('starting...');
  await window.saveSettings({username,ram_mb:ram,version:selected.id});
  await window.play({username,ram_mb:ram,version:selected.id,url:selected.url});
  polling=true;poll();
});

function showStatus(msg,err){const el=$('status');el.textContent=msg;el.className='status'+(err?' err':'');}

window.onProgress=(status,done,total)=>{
  showStatus(status,status.startsWith('error'));
  if(total>0){$('fill').style.width=Math.round(100*done/total)+'%';}
  if(status==='Game launched'||status.startsWith('error'))$('play').disabled=false;
};

async function poll(){if(!polling)return;try{const p=JSON.parse(await window.getProgress());showStatus(p.status,p.status.startsWith('error'));if(p.total>0)$('fill').style.width=Math.round(100*p.done/p.total)+'%';if(!p.active){polling=false;$('play').disabled=false;if(!p.status.startsWith('error')){showStatus('Game launched');$('fill').style.width='100%';}}}catch(e){}setTimeout(poll,400);}

init();
</script></body></html>`

func main() {
	exePath, _ := os.Executable()
	baseDir = filepath.Dir(exePath)
	gameDir = filepath.Join(baseDir, ".minecraft")
	assetsDir = filepath.Join(baseDir, "assets")
	librariesDir = filepath.Join(baseDir, "libraries")
	versionsDir = filepath.Join(baseDir, "versions")
	nativesDir = filepath.Join(baseDir, "natives")
	settingsPath = filepath.Join(baseDir, "settings.json")

	os.MkdirAll(gameDir, 0755)
	os.MkdirAll(assetsDir, 0755)
	os.MkdirAll(librariesDir, 0755)
	os.MkdirAll(versionsDir, 0755)
	os.MkdirAll(nativesDir, 0755)

	w := webview.New(false)
	defer w.Destroy()
	currentWV = w
	w.SetTitle("Minecraft Launcher")
	w.SetSize(720, 780, webview.HintNone)

	w.Bind("getVersions", func() (string, error) {
		var m VersionManifest
		if err := fetchJSON(versionManifestURL, &m); err != nil {
			return "[]", err
		}
		var list []versionItem
		for _, v := range m.Versions {
			if v.Type == "release" || v.Type == "snapshot" {
				list = append(list, v)
			}
		}
		b, _ := json.Marshal(list)
		return string(b), nil
	})

	w.Bind("getSettings", func() (*Settings, error) {
		return loadSettings(), nil
	})

	w.Bind("saveSettings", func(s Settings) error {
		saveSettings(&s)
		return nil
	})

	w.Bind("play", func(opts PlayOpts) (string, error) {
		go func() {
			err := installAndLaunch(opts.Version, opts.URL, opts.Username, opts.RAM)
			if err != nil {
				logln("error: %v", err)
				jsProgress("error: "+err.Error(), 0, 0)
			} else {
				jsProgress("Game launched", 0, 0)
			}
		}()
		return "ok", nil
	})

	w.Bind("getProgress", func() (string, error) {
		b, _ := json.Marshal(map[string]any{"active": false, "status": "running", "done": 0, "total": 0})
		return string(b), nil
	})

	w.SetHtml(indexHTML)
	w.Run()
}
