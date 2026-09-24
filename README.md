# Kinakazo

Windows 应用原生隔离打包仓库。

## 安装使用

需要 Windows 11 x64 24H2 或更高版本，安装包需为当前 Windows 用户 SID 构建。

从 [Actions](https://github.com/Kinakaze/Kinakazo/actions/workflows/build.yml) 下载并解压构建产物，然后：

1. 双击 `Kinakaze.cer`，选择「安装证书」→「本地计算机」→「将所有的证书都放入下列存储」→「受信任的人」，完成证书安装。首次安装时操作一次即可。
2. 双击 `.msix` 文件，点击「安装」。
3. 从开始菜单打开 `QQNT.Isolated`，以后直接运行即可。

# 第三方组件

- 各种应用打包，使用受其条款约束。本项目不是任何官方项目。
- 未对任何应用进行修改与Hook，仅使用系统机制进行隐私安全约束。


# Thanks
[微软应用隔离](https://learn.microsoft.com/en-us/windows/win32/secauthz/app-isolation-overview)。
