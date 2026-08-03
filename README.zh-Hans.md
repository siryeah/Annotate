# Annotate 简体中文定制版

Annotate 是一款轻量的 macOS 屏幕标注工具，适合直播授课、网页讲解和软件实操演示。

> 本项目基于 [epilande/Annotate](https://github.com/epilande/Annotate)
> 进行二次开发。感谢原作者 Emmanuel Pilande 开源这款优秀的 macOS
> 屏幕标注工具，让我能够在现有项目基础上，快速根据直播授课和屏幕演示的实际需要进行调整。
>
> 本定制版由 **AI 产品经理四月**（GitHub：
> [@siryeah](https://github.com/siryeah)）修改与维护，属于非官方定制版本。

项目的产品初衷、关键决策、代码入口和后续接手说明见
[《产品决策与开发交接文档》](PROJECT_HANDOFF.zh-Hans.md)。

## 定制功能

- 设置页、菜单栏、工具名称和操作提示支持简体中文。
- 矩形工具改为圆角矩形，绘制、选择和擦除使用一致的圆角边界。
- 新增“画笔”光标并设为新安装的默认样式；石墨黑笔身保持固定，落笔笔尖跟随当前标注颜色。
- 淡出模式支持调整 1–8 秒显示时长，也可以切换为“保留”模式。
- `⌥Z` 默认开启或退出画笔，`⌥X` 全局开启或关闭光圈与点击效果。
- 标注时仍可用空格、方向键和 Page Up/Down 控制开启标注前使用的 PPT、PDF 或网页幻灯片。
- 进入画笔状态后，光圈和点击效果会临时隐藏；退出画笔后自动恢复。
- 展开菜单栏时暂停自定义光标动画和鼠标追踪，减少菜单操作卡顿。

## 安装

从 [Releases](https://github.com/siryeah/annotate-cn-custom/releases/latest)
下载适合 Apple Silicon Mac 的安装包：

- `Annotate-CN-1.4.1-arm64.dmg`：打开后将 Annotate 拖入“应用程序”。
- `Annotate-CN-1.4.1-arm64.zip`：解压后将 `Annotate.app` 拖入“应用程序”。

当前定制包使用临时签名，尚未经过 Apple 公证。如果首次启动被系统拦截，请右键应用并选择“打开”。

## 使用方法

1. 启动应用，在菜单栏打开“设置”。
2. 按 `⌥Z` 进入画笔状态，在鼠标所在的显示器上标注；再次按 `⌥Z` 或按 `Esc` 退出。
3. 按 `⌥X` 开启光圈和点击效果，此时仍可正常操作网页或其他应用。
4. 在“光标”中选择“画笔”，可按需调整光标大小。
5. 在“工具”中调整淡出时长，或选择“保留”让标注持续显示。
6. 在“通用 → 演示翻页”中开启演示翻页并完成 macOS 权限授权。播放网页 HTML 幻灯片时，请先点击幻灯片页面，再按 `⌥Z` 开始标注。

标注状态下，空格、左/右/上/下和 Page Up/Down 会发送给开启标注前使用的应用；长按不会连续跳过多页。正在使用 Annotate 文字工具输入时，这些按键全部留给文字编辑，不会触发翻页。`Esc` 只退出 Annotate 标注，不会发送给 PPT 或浏览器。

工具单键沿用原版默认值，例如 `P` 为画笔、`A` 为箭头、`L` 为直线、`R` 为圆角矩形；所有工具快捷键均可在“快捷键”页面修改。

## 本地构建

需要 macOS 14 或更高版本以及 Xcode。

```sh
xcodegen generate
xcodebuild -project Annotate.xcodeproj -scheme Annotate -configuration Debug build
```

也可以运行测试：

```sh
xcodebuild -project Annotate.xcodeproj -scheme Annotate test
```

定制版使用独立 Bundle ID `com.siryeah.Annotate`，不会与原版共用应用身份。当前关闭了 Sparkle 自动更新，避免原版更新覆盖定制功能。

## 开源许可与署名

本项目继续遵循 MIT License。原作者版权与许可声明完整保留在
[LICENSE](LICENSE) 中，详细署名和修改说明见 [NOTICE.md](NOTICE.md)。
