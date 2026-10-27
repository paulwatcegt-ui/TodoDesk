# 待办 · DaiBan v1.2.0

Windows 11 极简本地待办清单。这一版提供正式 Windows 安装包和单文件应用。

## 下载

- **推荐安装包**：`DaiBan-1.2.0.msi`
- **便携版**：`DaiBan.exe`
- 校验文件：对应的 `.sha256`

## 安装

1. 下载 `DaiBan-1.2.0.msi`。
2. 双击安装包，按 Windows 安装向导完成。
3. 从开始菜单或桌面启动「待办」。

安装到当前用户目录，不需要管理员权限：

- 程序：`%LOCALAPPDATA%\Programs\DaiBan\DaiBan.exe`
- 数据：`%APPDATA%\DaiBan`
- 开始菜单、桌面和 Windows「已安装的应用」中都会出现「待办」

如果不想安装，下载 `DaiBan.exe` 便携版直接运行即可；数据位置不变。

## 本版本

- 完整的 Windows Installer（MSI）安装/卸载。
- 原生 `DaiBan.exe`，无控制台、无外部脚本文件。
- 跟随系统 / 浅色 / 深色外观。
- 自定义任务保存文件夹，切换时保护已有数据。
- 修复窗口标题栏拖动。
- 单文件便携版。
- 安装目录中只保留一个 `DaiBan.exe`。

## 签名说明

本版本**没有使用商业代码签名证书**。Windows 可能显示“未知发布者”，但安装包使用系统签名的 Windows Installer 安装。请只从本仓库的 Releases 下载，并使用附带的 `.sha256` 校验文件：

```powershell
Get-FileHash .\DaiBan-1.2.0.msi -Algorithm SHA256
```

系统要求：Windows 11，系统自带组件即可，不需要安装额外运行库。
