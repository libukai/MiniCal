# MiniCal

轻量的 macOS 菜单栏日历，支持农历、节气、节日、系统日程和桌面 Widget。

**Apple Silicon / ARM64 · macOS 14+ · Swift / SwiftUI / AppKit · MIT**

## 功能

- 六周月历、年月导航、农历闰月、节气与节日标签。
- 休假和补班角标；当前包含 2026 年官方数据。
- 点击菜单栏展开，失焦收起；图钉固定为独立窗口。
- EventKit 日历与提醒事项、日历筛选、事件创建／编辑／移动／删除。
- 日历创建与删除、本地 ICS 预览导入、交给系统日历处理的订阅。
- 四页设置：通用、事件、样式、状态栏；六种状态栏模块可排序。
- 小、中、大 Widget，午夜 Timeline 和日期深链。

## 安装与签名

从 [GitHub Releases](https://github.com/libukai/MiniCal/releases) 下载 ARM64 DMG，将 `MiniCal.app` 拖入 Applications，再打开应用。日历及提醒事项权限在“事件”页按需授权。

下载文件要区分两种发行形式：

| 形式 | 用途 | 默认 Gatekeeper 的安装体验 |
| --- | --- | --- |
| `*-local.dmg` | 本地构建、开发和测试 | ad-hoc 签名、未经公证，不能保证下载后直接打开 |
| 已公证的 Developer ID 发行版 | 面向普通用户 | 使用 Developer ID 签名、公证并附带票据 |

当前项目可以自行编译使用。本地运行成功和 `codesign --verify` 通过不等于公开下载包通过 Gatekeeper。正式发行流程见 [发布指南](docs/RELEASING.md)。

## 从源码运行

需要 Apple Silicon Mac、Xcode 16+ 或带 Swift 6.0+ 的 Command Line Tools。脚本采用当前 `xcrun` 的 macOS SDK，仅构建 ARM64。

```sh
./script/build_and_run.sh --verify
./script/test.sh
```

生成 `dist/MiniCal.app`。只构建不启动：

```sh
./script/build.sh --release
./script/package.sh
```

只使用虚拟数据进行 UI 测试：

```sh
./script/build_and_run.sh --verify --fixtures --calendar-window --settings
```

虚拟模式使用内存数据，适合验证 CRUD 与界面；它不写入真实日历或用户偏好，不注册登录项或申请通知权限。日常运行不要带 `--fixtures`。

## 使用

左右方向键翻月，上下方向键翻年，空格回今天；Shift 点击箭头翻年。底部滑杆图标进入设置。菜单栏位置由系统提供的 ⌘ 拖动操作调整。

在桌面“编辑小组件”中查找 MiniCal。中、大尺寸可点击任意日期，小尺寸整体点击定位今天。Widget 独立计算公开日历信息，不读取私人事件。

## 数据边界

节气计算支持 1900—2100，使用近似模型，临近午夜可能有跨日误差。未收录年份不猜测休班角标。部分纪念日标签采用历史固定日期，不等同于法定节假日。来源见 [NOTICE](NOTICE.md)。

## 项目结构

```text
Sources/MiniCalCore     月历、农历、节气与假日数据
Sources/MiniCalData     EventKit、ICS、虚拟数据
Sources/MiniCal         应用、窗口、设置与编辑界面
WidgetExtension        WidgetKit 扩展
Tests                  核心、数据和状态测试
script                 构建、测试、打包、公证与图标生成
config                 Widget entitlements
```

本地验证环境为 macOS 27 / Swift 6.4 / SDK 27。ARM64 的 macOS 15 与 macOS 26 构建及测试结果见 [GitHub Actions](https://github.com/libukai/MiniCal/actions)。最低部署目标为 macOS 14，该版本尚未实际验收。

参与贡献请阅读 [CONTRIBUTING](CONTRIBUTING.md)。许可见 [LICENSE](LICENSE)。
