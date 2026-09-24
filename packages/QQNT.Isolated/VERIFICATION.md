# 本机验证记录

验证时间：2026-09-24 15:03（UTC+08:00）。环境：Windows 11 Pro 25H2，26200.9168，x64。

已安装包：`QQNT.Isolated_9.9.33.52249_x64__61fs737rmxvcr`。QQ 程序版本：9.9.33-52230。

产物：`QQNT.Isolated.msix`，521197493 字节。SHA-256：

```text
563EC342972AC4B370770A00D79718EA3828553C2119414BF60E25DD624B52EA
```

## 结果

| 检查 | 实测结果 |
| --- | --- |
| 编译、打包与签名 | GCC 编译通过；MakeAppx 清单验证通过；SignTool 签名和验证通过；MSIX 已安装 |
| 启动 | QQ 主进程 PID 23884 于 15:00:08 启动；15:03:24 仍存活，窗口句柄有效且 Responding=True |
| 进程边界 | 启动器及当次枚举的 QQ 子进程均为 AppContainer，完整性级别均为 Low（S-1-16-4096），包身份与正式包一致 |
| 原生目录解析 | SHGetFolderPath 的 Documents、RoamingAppData、LocalAppData、Profile 全部返回包内私有路径；PATH_VALIDATION_FAILURES=0 |
| 宿主配置 | 目录探测前后，宿主 User Shell Folders 的 AppData、Local AppData、Personal 值保持不变 |
| 宿主文件读取 | 在项目目录、用户目录分别创建测试文件，容器内打开均返回 ERROR_ACCESS_DENIED（5） |
| 宿主文件写入 | 同上，申请写入句柄返回 ERROR_ACCESS_DENIED（5）；测试文件内容未变 |
| 宿主进程访问 | 容器内申请宿主 PowerShell 的 PROCESS_VM_READ / PROCESS_VM_WRITE 返回 ERROR_ACCESS_DENIED（5） |
| 启动入口 | 桌面“QQ 隔离版”指向 shell:AppsFolder\\QQNT.Isolated_61fs737rmxvcr!QQ；项目提供 Start-QQ.cmd |

原始证据保存于 `build/isolation-processes.json`、`build/isolation-probe.json`、`build/native-paths.txt`。这些文件记录一次实测，进程 ID 和进程数量会随运行变化。

## 实现范围

隔离和目录重定向使用 Windows AppSilo / AppContainer、打包的 User.dat / Registry.dat、子进程环境变量及系统目录 API。没有加入自定义 Hook、注入 DLL 或修改 QQ 二进制。QQ 原有 AVSDK 自带的 libMinHook DLL 随原程序保留；隔离启动器不加载或调用它们。

能力清单仅包含 internetClient、isolatedWin32-sysTrayIcon、isolatedWin32-profilesRootMinimal、isolatedWin32-volumeRootMinimal。后两项用于必要的根路径解析；上述宿主测试文件仍被拒绝访问。未声明 isolatedWin32-promptForAccess 或 broadFileSystemAccess，因此没有依靠外部目录授权弹窗完成启动。

为解决 QQ 初始化兼容问题，命令行包含 `--no-sandbox`，停用 Chromium 内部沙箱；外层 Windows AppContainer 隔离已经由进程令牌和访问探测验证。原生注册表视图及目录重定向机制参考 [Microsoft 应用隔离说明](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview) 和 [MSIX 虚拟化说明](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization)。

当前验证覆盖安装、窗口启动、进程身份、目录解析和上述资源访问边界，未自动验证发送消息、音视频、插件、自动更新或长期运行稳定性。测试拒绝访问不能替代完整的安全审计。其他账户或机器需要重新生成包含其用户 SID 的 Registry.dat；启动和构建方法见 README.md。
