# 第三方组件

- QQ NT、QQ 名称及图标属于腾讯，使用受其条款约束。本项目不是腾讯官方项目；QQ 程序不存入 Git 历史，按需从官网配置提供的地址获取。
- QQ 自带的 AVSDK 可能包含 libMinHook 等第三方组件；它们作为原程序的一部分保留。本项目隔离启动器不依赖这些库进行目录重定向。
- Windows SDK BuildTools 来自 Microsoft 官方 NuGet 包，安装时遵循其 [许可条款](https://aka.ms/WinSDKLicenseURL)。仓库固定版本及 SHA-256，不把工具二进制提交到仓库。
- GCC / MinGW-w64 通过 MSYS2 使用；7-Zip 用于解压官方安装器。它们各自的许可证适用。
- 应用 ZIP 和 `files.sha256.json` 用于校验传输损坏，不是发布者数字签名。安装时的本机签名只建立本机包信任，不能替代对构建来源和下载来源的信任。
