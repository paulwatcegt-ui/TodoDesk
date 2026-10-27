# 待办 · DaiBan v1.1.0

Windows 11 极简本地待办清单。无账号、不联网，安装后从开始菜单使用。

## 下载与安装

1. 下载下方的 `DaiBan-v1.1.0.zip`。
2. 解压到任意目录。
3. 在解压后的目录打开 PowerShell，运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

4. 按 `Win` 键搜索「待办」启动。

安装只在当前用户范围进行，不需要管理员权限：

- 程序：`%LOCALAPPDATA%\Programs\DaiBan`
- 默认数据：`%APPDATA%\DaiBan`
- 开始菜单：`待办`

卸载：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\DaiBan\uninstall.ps1"
```

## 本版本

- 跟随系统 / 浅色 / 深色外观。
- 自定义任务保存文件夹，切换时自动保护已有数据。
- 修复窗口标题栏拖动。
- 现代化原生文件夹选择器。
- 本地自动保存，无网络请求。

## 签名说明

本版本**没有使用商业代码签名证书**，因此 Windows 可能把下载的脚本标记为来自“未知发布者”。应用由系统签名的 Windows PowerShell/WPF 组件承载，安装脚本只复制文件并创建当前用户的开始菜单快捷方式。若需要校验下载文件，请使用 Release 附件中的 `.sha256`：

```powershell
Get-FileHash .\DaiBan-v1.1.0.zip -Algorithm SHA256
```

系统要求：Windows 11，系统自带 Windows PowerShell 5.1。
