# Kinakazo

Windows 应用原生隔离打包仓库。每个应用位于 `packages/<包名>/`，当前支持 **QQNT.Isolated**。隔离层使用 Windows AppSilo / AppContainer 和原生目录重定向，不使用 Hook 或 DLL 注入。

## 按需构建

在 GitHub **Actions → Build package on demand → Run workflow** 中选择 `QQNT.Isolated`。也可以执行：

```sh
gh workflow run build.yml --repo Kinakaze/Kinakazo -f package=QQNT.Isolated
```

只有 `workflow_dispatch` 触发，没有 push、PR、定时或全量自动构建。每次运行读取 QQ 官网下载配置，下载当时发布的最新 x64 安装器，验证腾讯 Authenticode 签名、解压程序、编译隔离启动器并验证 MSIX 清单。下载失败会直接报错，不会改用旧版本。

完成后在该次运行的 **Artifacts** 下载 ZIP、SHA-256 和 `upstream.json`。产物保留 14 天，不自动发布 Release。`upstream.json` 记录上游版本、原始下载地址、签名者、安装器 SHA-256 和构建版本。

## 安装产物

要求 Windows 11 **x64** 24H2（26100）及以上。解开 Actions 下载的外层 ZIP，再解开里面的应用 ZIP，运行 `Install.cmd`。之后从桌面“QQ 隔离版”启动。

原生 ProfileList 重定向必须包含目标用户 SID，所以 CI 产物是可安装文件包，不是绑定 CI 账户的 MSIX。安装脚本会在本机生成 Registry.dat，下载固定版本且校验哈希的微软打包工具，生成或复用本用户代码签名证书，完成 MSIX 打包和安装。首次信任本机证书可能弹出 Windows UAC；这与 QQ 访问外部目录的授权不同。签名私钥保留在本机证书库，不上传 CI。

QQ 的 Chromium 内部沙箱因兼容性而关闭；外层 Windows AppContainer 仍生效。已验证的运行边界及未覆盖功能见 [QQ 文档](packages/QQNT.Isolated/README.md) 和 [本机验证记录](packages/QQNT.Isolated/VERIFICATION.md)。Windows Server CI 只验证构建，不能代替 Windows 11 上的交互启动与隔离测试。

## 本地构建

需要 PowerShell、MinGW-w64 GCC、7-Zip 和网络。Windows SDK 工具会自动下载并校验；无需在 CI 配置 PAT 或签名私钥。

```powershell
.\tests\Test-Repository.ps1
.\scripts\Build-Package.ps1 -Package QQNT.Isolated -Compiler 'C:\msys64\mingw64\bin\gcc.exe' -Revision 1
# 也可使用已有完整 QQ 目录，不访问上游：
.\scripts\Build-Package.ps1 -Package QQNT.Isolated -SourceDirectory 'D:\Apps\QQ' -Compiler 'C:\msys64\mingw64\bin\gcc.exe' -Revision 2
```

输出位于 `artifacts/QQNT.Isolated/`。版本格式为 `<上游三段版本>.<构建序号>`，CI 使用 workflow run number；本地应递增 `-Revision`。已有本机测试包的末段版本较大时，安装同一上游版本需使用更大的序号或等待上游版本升级，不要卸载含有需要保留数据的旧包。

## 扩展应用

```text
.github/workflows/build.yml     # 按需选择包
scripts/                       # 共用调度与 SDK 工具获取
tests/                         # 源码、下载解析、权限边界检查
packages/
  QQNT.Isolated/
    package.json               # 包身份、上游配置、构建入口
    layout/                    # MSIX 清单与图标
    src/                       # 原生启动器及探测程序
    scripts/                   # 下载、构建、安装、运行检查
```

新增应用时添加对应目录、`package.json` 和 `scripts/Build.ps1`，再把包名加入 workflow 的 `package.options`。共用入口只分派选中的包。

QQ 和微软工具的所有权及条款见 [第三方说明](THIRD_PARTY.md)。仓库只提交源码和打包配置；QQ 二进制、证书私钥、构建缓存、调试转储和个人运行数据均不提交。

参考：[GitHub 手动工作流](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatch)、[QQ 官方下载页](https://im.qq.com/pcqq/index.shtml)、[微软应用隔离](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview)。
