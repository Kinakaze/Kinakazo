# QQNT.Isolated

QQ NT 的原生 Windows 隔离包，要求 Windows 11 x64 24H2（26100）及以上。AppSilo / AppContainer 提供进程及资源隔离；User.dat、Registry.dat 和启动器环境变量把已知用户文件夹指向包的私有目录。隔离层不使用 Hook、DLL 注入或 QQ 二进制补丁。

## 安装与启动

从 Kinakaze/Kinakazo 的 GitHub Actions 下载构建产物，完整解压后双击 `Install.cmd`。安装器校验文件哈希，为当前用户生成 ProfileList 注册表覆盖，使用微软 SDK 打包、在本机签名并安装。首次信任签名证书可能需要 UAC；QQ 本身始终以 AppContainer 身份运行。安装时需联网获取固定版本的微软 SDK，后续使用缓存。

安装后双击桌面“QQ 隔离版”或包内的 `Start-QQ.cmd`。维护命令：

```powershell
.\scripts\Start.ps1
.\scripts\Inspect-Processes.ps1
.\scripts\Stop.ps1
```

`Start.ps1` 等待窗口并检查进程容器身份。`Stop.ps1` 只停止此包目录下的进程。更新前请正常退出隔离版 QQ；同一包身份的更新保留包数据。卸载可能删除包数据，应先备份。

可以只准备当前用户的签名 MSIX 而不安装：

```powershell
.\scripts\Install.ps1 -PrepareOnly
```

`-CertificateThumbprint` 可指定本用户证书库内的匹配证书；默认复用或生成 `CN=Ai2Web` 本机证书。`-SdkDirectory` 可指定已有 x64 MakeAppx / SignTool 目录。私钥不会写入产物或发送到 GitHub。最终 MSIX 绑定生成它的用户 SID，不能直接复制给其他账户；其他账户应运行原始 ZIP 中的安装入口。

## 隔离与目录

清单使用 `uap10:TrustLevel="appContainer"` 及 `previewsecurity2:RuntimeBehavior="appSilo"`，启动器在容器外拒绝运行。完整程序安装到 WindowsApps，不依赖原 QQ 外部安装目录。

只声明 internetClient、isolatedWin32-sysTrayIcon、isolatedWin32-profilesRootMinimal、isolatedWin32-volumeRootMinimal。最小根路径能力用于路径解析，不开放个人文件读写。没有 promptForAccess 或 broadFileSystemAccess，不靠逐个外部目录授权完成启动。用户主动通过文件选择器或拖放选择的外部文件仍可能获得系统隐式授权。

QQ 初始化需要 `--no-sandbox`：Chromium 自己的内部沙箱关闭，整个应用及子进程由外层 Windows AppContainer 隔离。不能把这理解为两层沙箱同时启用，也不保证所有插件、硬件和音视频功能可用。

启动器数据根目录：

```text
%LOCALAPPDATA%\Packages\QQNT.Isolated_61fs737rmxvcr\AC\QQIsolated\
  launcher.log
  Chromium\
  Profile\
```

Profile 包含独立的文档、桌面、下载、图片、音乐、视频、AppData、临时目录。Windows 的 LocalAppData API 还会追加 `Packages\<包身份>\AC`。目录重定向不修改宿主 HKCU/HKLM 配置；其他适用的 COW 文件和注册表写入由 Windows 虚拟化处理。

## 运行检查

先关闭隔离版 QQ，再执行：

```powershell
.\scripts\Test-Isolation.ps1
.\scripts\Test-NativePaths.ps1
.\scripts\Start.ps1
.\scripts\Inspect-Processes.ps1 -OutputPath .\build\isolation-processes.json
```

边界探测只创建随机测试文件，检查宿主文件读写及宿主进程内存访问被拒绝。目录探测检查 Windows 原生 API 返回内部路径，并检查宿主已知文件夹配置未变。报告输出到 `build/`。CI 中的 Windows Server 不等于 Windows 11 运行验证；历史本机验证位于源码仓库同目录的 VERIFICATION.md。

## 从源码构建

在仓库根目录运行：

```powershell
.\scripts\Build-Package.ps1 -Package QQNT.Isolated -Compiler 'C:\msys64\mingw64\bin\gcc.exe' -Revision 1
```

默认从 WinGet 的 Tencent.QQ.NT 清单解析最新 x64 下载地址，下载并强制校验清单中的 SHA-256，只解压而不执行安装器。也可以指定 `-SourceDirectory` 使用已有完整 QQ 目录。产物为可跨账户准备安装的 ZIP；版本、清单来源、下载地址及安装器 SHA-256 见产物 `upstream.json`。本地访问 GitHub API 遇到限流时，可设置临时 GH_TOKEN；CI 自带只读令牌，无需配置 PAT。

## 按需 CI

在 GitHub Actions 的 **Build package on demand → Run workflow** 中选择 `QQNT.Isolated`，或执行：

```sh
gh workflow run build.yml --repo Kinakaze/Kinakazo -f package=QQNT.Isolated
```

工作流只在手动触发时构建选中的包，不设置 push、PR、定时或全量构建。完成后从该次运行的 Artifacts 下载 ZIP、校验值和 upstream.json，产物保留 14 天，不自动发布 Release。最新版以 WinGet 收录的最高稳定版本为准。

CI 使用 `<上游三段版本>.<workflow run number>` 作为 MSIX 版本。本地构建可通过 `-Revision` 指定末段；更新必须高于已安装包版本。不要为了降级而卸载含有需要保留数据的包。

未来新增应用时，在 `packages/<包名>/` 提供 package.json、scripts/Build.ps1，并把包名加入 workflow 的 package.options。共用入口 scripts/Build-Package.ps1 只分派所选包。

参考：[应用隔离](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview)、[隔离能力](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-supported-capabilities)、[MSIX 虚拟化](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization)。
