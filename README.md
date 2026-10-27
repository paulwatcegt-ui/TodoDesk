# 待办 · DaiBan

一款只做一件事的 Windows 11 桌面待办清单。原生 WPF 界面，单文件应用，无账号、不联网、没有多余的模块。

[**下载最新版本**](https://github.com/paulwatcegt-ui/to-do/releases/latest) · [查看源码](https://github.com/paulwatcegt-ui/to-do)

| 浅色 | 深色 |
| --- | --- |
| ![浅色界面](docs/preview-light.png) | ![深色界面](docs/preview-dark.png) |

## 功能

- 输入待办后按 `Enter` 添加，`Ctrl+N` 随时回到输入框。
- 点击左侧圆圈完成或恢复任务。
- 双击标题，或悬停后点击铅笔，进入行内编辑。
- 删除和批量清除已完成任务都支持撤销。
- 自动保存在本机；不需要登录，不发起网络请求。
- 设置中可切换**跟随系统 / 浅色 / 深色**，主题即时生效。
- 设置中可**自定义任务数据的保存文件夹**。
- 窗口支持拖动、边缘调整大小，右上角提供设置、最小化和关闭。
- 安装后开始菜单和桌面都有「待办」，可在 Windows「已安装的应用」中卸载。

## 安装

需要 Windows 11。系统自带的 .NET Framework 4.8 / Windows PowerShell 组件即可，不需要安装额外运行库。

1. 从 [Releases](https://github.com/paulwatcegt-ui/to-do/releases/latest) 下载 `DaiBan-1.2.0.msi`。
2. 双击 MSI，按 Windows 安装向导完成安装。
3. 从开始菜单或桌面启动「待办」。

安装特点：

- 安装到 `%LOCALAPPDATA%\Programs\DaiBan`，当前用户范围，不需要管理员权限。
- 安装目录中只有一个 `DaiBan.exe`，没有脚本、没有控制台窗口。
- 自动创建开始菜单和桌面快捷方式，并在 Windows「已安装的应用」中注册卸载项。
- 升级时会保留你的设置和待办数据。

如果不想安装，也可以直接下载 Release 中的 `DaiBan.exe` 便携版运行。

## 数据

默认数据目录：

```text
%APPDATA%\DaiBan
```

其中：

- `todos.json`：待办数据
- `settings.json`：外观和保存位置设置
- `todos.json.bak` / 带时间戳的备份：自动保护旧数据

数据只保存在本机。应用没有遥测、网络请求、账号系统或自动更新。

在设置中可以切换主题和任务保存目录。切换目录时，如果目标目录已有 `todos.json`，应用会先备份再覆盖。原目录的文件不会被自动删除。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 聚焦添加框 | `Ctrl+N` |
| 打开/关闭设置 | `Ctrl+,` |
| 添加 | `Enter` |
| 保存行内编辑 | `Enter` |
| 取消编辑 / 关闭设置 / 关闭提示条 | `Esc` |

## 卸载

打开 Windows「设置 → 应用 → 已安装的应用」，找到「待办」，选择卸载。卸载程序由 Windows Installer 提供。

卸载默认保留 `%APPDATA%\DaiBan` 中的待办数据；如确定不再使用，可手动删除该目录。

## 开发

这个项目采用「原生 WinExe 启动器 + WPF 界面」的结构。发布给用户的安装目录里只有 `DaiBan.exe`；界面资源和应用逻辑在构建时嵌入可执行文件。

```text
app/
  DaiBan.ps1          WPF 界面逻辑、设置、数据读写
  ui.xaml             窗口和样式
  themes/             浅色与深色资源
  app.ico             图标
host/
  DaiBanHost.cs       原生启动器：加载内置 WPF 资源，启动窗口
  build.ps1           构建 dist/native/DaiBan.exe
installer/
  DaiBan.wxs          WiX MSI 安装定义
  build-msi.ps1       构建 MSI（需要 WiX v3）
tests/
  validate.ps1        语法、XAML、主题和文件校验
```

构建应用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\host\build.ps1
```

构建 MSI（需要 WiX v3 的 `candle.exe` / `light.exe`）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\build-msi.ps1
```

校验：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

详细的启动链路和数据流见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 签名

当前发布包没有使用商业代码签名证书。Windows 可能显示“未知发布者”；MSI 使用系统 `msiexec` 安装。签名准备和证书配置见 [docs/SIGNING.md](docs/SIGNING.md)。

## 已知限制

- 仅针对 Windows 11 测试和优化。
- 界面语言目前只有简体中文。
- 没有云同步、多设备、提醒通知或自动更新；这是刻意的范围限制。
- 没有代码签名证书时，部分启用了智能应用控制/严格应用控制的机器可能拦截首次运行；安装器为 MSI，可在系统允许的范围内使用。
- 原生启动器嵌入的是现有 WPF 界面和逻辑，并非完全重写的纯 C# 应用；对用户而言安装目录中只有单一 `DaiBan.exe`，没有可见脚本。

## 参与

欢迎聚焦于“极简本地待办”范围的改动。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)

---

## English quick start

DaiBan is a local-first, minimalist todo app for Windows 11. Download the MSI from [Releases](https://github.com/paulwatcegt-ui/to-do/releases/latest), run it, and launch “待办” from the Start menu or desktop. The installed application is a single native `DaiBan.exe`; no console or external scripts are exposed to the user.

Data stays in `%APPDATA%\DaiBan`. The app never connects to the network. Build instructions are above; the project is MIT licensed.
