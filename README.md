# TodoDesk · 待办

把事情，一件件做好。一款极简、本地优先的 Windows 桌面待办应用。

原生 WPF 窗口，无账号、无云同步、无遥测。可直接从源码运行，也能构建成单个 `DaiBan.exe`。采用 [MIT 许可证](LICENSE)，欢迎使用、修改和贡献。

项目维护：[宋培恩](https://github.com/paulwatcegt-ui)。问题反馈和改进建议请提交到本仓库 Issues。软件及其本地数据不包含遥测或云端同步。

设置底部可查看完整 MIT 许可；单文件 EXE 内也嵌入许可证原文，保留既有版权与许可声明。

| 浅色 | 深色 |
| --- | --- |
| ![浅色](docs/preview-light.png) | ![深色](docs/preview-dark.png) |

## 下载安装

在 [GitHub Releases](https://github.com/paulwatcegt-ui/TodoDesk/releases/latest) 下载 **TodoDesk-1.3.0-x64.msi**，双击启动中文安装向导。安装时可浏览或输入路径，默认是当前用户的 `%LOCALAPPDATA%\Programs\TodoDesk`。请选择自己有写入权限的文件夹。

安装后通过桌面或开始菜单的 TodoDesk 打开；也可下载便携版 TodoDesk.exe。卸载通过 Windows“已安装的应用”进行，保留待办数据。下载页附有 SHA256SUMS.txt。当前发行版未签名，严格的企业应用控制策略可能阻止启动，详见 [发布说明](RELEASE_NOTES.md)。

## 本地预览：无需下载应用安装包

需要 **Windows 11**，使用系统自带的 **Windows PowerShell 5.1 / .NET Framework 4.8**。不需要 Node.js、npm、.NET SDK 或第三方依赖。

1. 克隆本仓库或将源码解压到本地。
2. 双击根目录的 **`preview.cmd`**。
3. 原生窗口直接打开，首次内置 5 条可操作的示例任务。添加、编辑、完成和设置均使用实际应用逻辑。

```powershell
git clone https://github.com/paulwatcegt-ui/TodoDesk.git
cd TodoDesk
.\preview.cmd
```

预览数据保存在 `.preview/data`，设置保存在 `.preview/config`，均已加入 Git 忽略列表。重新打开会保留试用中的修改，不读取正式版的 `%APPDATA%\DaiBan` 数据。

首次希望从空列表开始，可运行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\preview.ps1 -Empty
```

修改源码后，关闭窗口并重新双击 `preview.cmd` 即可查看，不需要构建或下载。这里打开的是实际的 Windows 应用窗口。

## 日常使用

双击 **`start.cmd`** 即可从源码使用正式数据目录，也可自行构建单文件版本。

- 输入待办后按 Enter 添加，Ctrl+N 聚焦输入框。
- 点击圆圈完成或恢复，双击标题或点击悬停出现的铅笔编辑。
- 用“全部 / 待办 / 已完成”切换视图，底部显示整个清单的完成进度。
- 未完成任务排在前面，全部视图中的已完成分组可以折叠；已完成筛选始终展示完成任务。
- 新增、编辑、完成、删除和清除已完成均支持提示条撤销；Ctrl+Z 可撤销任务操作，文本框内优先保留文字撤销。
- 设置支持跟随系统、浅色和深色主题，以及自定义保存目录。
- 本地 JSON 自动保存，覆盖写入保留 `.bak` 备份。

底部只有在已成功写入、或已从磁盘读到有效清单时才显示“数据已保存到本机”。新空列表不提前显示已保存；写入失败会明确提示并保留窗口内更改，关闭时重试，仍失败则取消关闭。读取失败或格式未知时禁用修改，不改写原文件及备份。设置文件读取失败时，主题仅本次生效，不覆盖原设置。

标题栏支持原生拖动、双击最大化和还原，提供最小化、最大化 / 还原、关闭按钮。最大化边界按当前显示器工作区计算。

进度代表当前清单的完成比例，不是每日统计。不包含云同步或自动更新。

## 任务优先级

输入框右侧的“高 / 中 / 低”按钮用于选择新任务优先级。任务文字直接表达优先级：**高为红色、中为正常文字色（深色主题为白色）、低为绿色**。双击标题或点击编辑按钮后，可在编辑框旁修改优先级；平常不显示任务优先级标签。悬停标题可查看完整文字和优先级。旧清单默认使用“中”，无需迁移，修改支持撤销。

开启优先级时，未完成任务按高、中、低排序，同级按创建时间倒序。用鼠标拖动任务文字区域可调整位置，靠近列表边缘会自动滚动，放置位置有细线提示。待办与已完成分组分别排序，不跨组拖动。手动顺序优先且会保存，之后新增或重新回到分组的任务追加在手动顺序之后。在设置中点击“恢复自动排序”可清除手动顺序。

## 任务计时与时间统计（默认关闭）

在设置中分别开启“任务计时”和“时间统计”，均为纯本地功能，无需联网。

- 新增输入框右侧为“提醒”和“计时”；选中“计时”后添加的任务立即开始计时。
- 鼠标移到未完成任务上，点击播放按钮开始计时，再次点击暂停。同一时间只计时一件任务，切换任务会先暂停前一件。
- 任务下方显示累计用时。完成、删除、关闭计时功能或关闭窗口都会暂停并保存；重新打开应用保持暂停，不计入关闭期间的时间。运行中每约 10 秒保存一次，异常退出可能损失最后约 10 秒。
- 开启统计后，“已完成”后出现“统计”。支持选择日期查看日、周（周一开始）、月和自定义日期范围，自定义的结束日期包含当天。
- 扇形图和图例展示每项任务的用时、占比及累计总时长。跨日期计时按实际重叠时段统计，包含已完成、归档及回收站的历史记录；永久清空回收站同时移除相应计时记录。
- 关闭功能不会删除历史数据。旧任务结构保持不变，计时记录和手动顺序作为现有 JSON 的可选字段保存，沿用原有原子写入与备份流程。

以上功能当前可通过源码本地预览，GitHub 的已发布安装包不会随工作区修改自动更新。

## 导入已有数据或备份

在设置的“保存位置”区域点击“导入备份”，选择之前保存的 `todos.json`、`todos.json.bak` 或复制出来的 TodoDesk JSON 备份。旧版仅包含任务列表的文件也可导入，设置文件 `settings.json` 不属于任务备份。

导入采用合并方式：保留现有任务，补充备份中的新任务、归档、回收站、计时记录和手动顺序；同 ID 的任务和计时记录保留当前内容。重复导入同一份备份不会重复添加记录。导入不改变主题、功能开关或数据保存位置。

应用先校验文件，再保存当前清单，并在当前数据目录生成独立的 `todos.before-import.时间.唯一标识.json` 完整备份；校验、当前清单保存或备份创建失败时停止导入。最终保存失败时会明确提示并保留窗口内数据，关闭时仍执行原有保存保护。导入完成后会告知自动备份路径。

回收站每一项都有“恢复”和“永久删除”。永久删除会二次确认，并移除该项的计时记录；其他任务不受影响。设置标题和关闭按钮固定显示，只有下方内容随滚轮滚动。

设置中的“优先级”和“时间提醒”开关默认开启。关闭只隐藏入口并停用相应着色或提醒触发，不删除已有的优先级、提醒时间；重新开启即可恢复。提醒、编辑、删除按钮平时隐藏，悬停任务行或通过键盘聚焦时显示。

编辑待办时，点击编辑框以外的地方会自动确认；Enter 确认、Esc 取消仍然可用。在编辑框内选择优先级不会因临时切换焦点而丢失正在输入的内容。

## 时间提醒设置

点击任务右侧的时钟按钮，可直接选择“10 分钟后 / 30 分钟后 / 1 小时后 / 明天 09:00”。也可以点击日期展开日历，分别填写时、分；支持加减按钮或键盘上下键微调。弹窗会预览实际提醒时间，过去或无效的时间不能保存。再次点击时钟可修改或移除，点击“取消”不改动已有提醒。设置后，任务标题下方显示提醒时间。

应用运行或最小化时，每 10 秒检查一次，到点弹出独立窗口并播放系统提示音。已完成任务不提醒，同一次提醒不重复弹出。关闭应用期间不会运行后台服务，错过的提醒会在下次打开应用时补发。

时间和已提醒标记保存在原本的 `todos.json` 中，作为可选字段加入；原有清单无需迁移。更改时间会重置已提醒状态。

新增输入框中的“设置提醒”可先为新任务选择时间，添加时一并保存；添加后会清空暂存的提醒时间。

## 数据与快捷键

新增框输入内容后，点击其他位置会自动添加；在输入框内选择优先级或设置提醒不会提前添加。Enter 和加号按钮仍然可用。

删除单条任务、清除已完成任务会移入设置里的“回收站”，可以恢复；只有在回收站中选择“清空回收站”并明确确认后才永久删除。“归档”位于“清除”之前，可将已完成任务留作记录，随后从设置里的“归档记录”查看或恢复。归档和回收站不计入当前进度，也不触发提醒。

当前任务仍在 `todos.json` 的 `items` 数组中，新增的 `archive` 和 `trash` 数组保存归档与回收站记录。全部内容在同一次原子写入中保存，恢复保留原完成状态、优先级和提醒。旧版文件缺少这两个数组时自动按空集合读取。

正式数据默认在 `%APPDATA%\DaiBan`：`todos.json` 是待办，`settings.json` 是外观和保存位置。沿用原项目的数据格式和目录。预览数据独立保存。

切换保存位置时，如果目标已有数据，应用会询问是否覆盖并先备份，原目录保留。重要清单请定期备份。

| 快捷键 | 操作 |
| --- | --- |
| Ctrl+N | 聚焦添加框 |
| Ctrl+, | 打开 / 关闭设置 |
| Enter | 添加 / 保存行内编辑 |
| Esc | 取消编辑 / 关闭设置 / 隐藏提示 |

## 构建与验证

```powershell
# 检查脚本、XAML、主题及发布元数据
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\validate.ps1

# 真实控件和存储逻辑的交互检查
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\smoke.ps1

# 原生窗口、焦点、命中测试及最大化工作区
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\window.ps1

# 提醒保存、触发、取消、最小化弹窗及紧凑文字检查
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\reminders.ps1

# 使用实际应用启动路径检查弹窗按钮的作用域和保存行为
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\reminder-entry.ps1

# 优先级、撤销、主题颜色与旧清单兼容性
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\priorities.ps1

# 任务排序、拖放、计时、日期统计及保存失败保护
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\tracking.ps1

# 构建单文件：dist/native/DaiBan.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\host\build.ps1
```

交互检查在 `.testdata/` 中生成独立数据，加 `-Screenshots` 可重新生成文档中的界面图片。

MSI 使用固定版本 WiX 3.14.1。准备脚本从官方 Release 下载便携工具并核对 SHA-256，解压到忽略提交的 `dist/tools`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\setup-wix.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\build-msi.ps1
```

输出 `dist/installer/TodoDesk-1.3.0-x64.msi`。EXE / MSI 默认未签名，见 [签名说明](docs/SIGNING.md)。安装包发布前需实测安装、升级与卸载。

## 开源与发布

```text
app/          WPF 界面、主题和本地数据逻辑
host/         单文件 Windows 启动器与构建脚本
installer/    WiX MSI 安装定义
tests/        静态验证与交互检查
docs/         界面预览与架构说明
preview.cmd   一键启动独立预览
start.cmd     使用正式数据的源码启动入口
```

GitHub Actions 在推送 main 和 PR 时验证源码、运行交互检查并构建 EXE。推送版本标签（例如 v1.3.0）会触发发布流程：运行检查、构建 EXE / MSI、实测自选目录的安装与卸载，并将文件和 SHA-256 校验值上传到 Releases。源码不包含用户数据或签名凭据。

贡献见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)，实现说明见 [架构文档](docs/ARCHITECTURE.md)。

本轮优化的修改文件、验证结果与未验证项见 [界面优化验收记录](docs/UI-REFINEMENT.md)。

## 署名与开源说明

项目沿用 MIT 许可证，完整条款见 [LICENSE](LICENSE)；其要求在分发软件副本或实质部分时保留版权及许可声明。使用、修改和商业分发的具体条件以许可证正文为准，参阅 [MIT 说明](https://choosealicense.com/licenses/mit/)。请保留现有贡献者的版权声明；项目维护者署名与版权权利人声明是不同的信息。

维护者可以使用自选公开昵称或 GitHub 名称，无需在界面公开真实姓名。README、设置中的维护者信息、LICENSE 和贡献指南共同构成项目的说明入口。后续引入第三方库、图标或字体时，再记录对应来源与许可证。

## English quick start

TodoDesk is a minimalist, local-first Windows 11 todo app. Clone this repo and double-click `preview.cmd` to try the real native app with isolated sample data. Use `start.cmd` for everyday use. Windows PowerShell 5.1 and .NET Framework 4.8 ship with Windows 11. Build a single executable with `host/build.ps1`. No accounts, network calls or telemetry. MIT licensed.
