# Annotate 简体中文定制版

Annotate 是一款轻量的 macOS 屏幕标注工具，适合直播授课、网页讲解和软件实操演示。

本分支在原版基础上完成了三项定制：

- 设置页、菜单栏、工具名称和操作提示支持简体中文。
- 矩形工具改为圆角矩形，绘制、选择和擦除都使用一致的圆角边界。
- 新增可选的“画笔”光标，并设为新安装的默认样式。画笔使用固定石墨灰 `#1F2937` 与白色描边，不跟随标注颜色变化；笔尖就是实际落笔点。

## 使用方法

1. 启动应用，在菜单栏打开“设置”。
2. 在“通用”中设置激活快捷键，推荐使用 `⌥Z`。
3. 在“光标”中选择“画笔”，可按需调整光标大小。
4. 按激活快捷键进入标注模式，在鼠标所在显示器上绘制。
5. 按 `Esc` 退出标注模式；是否自动清除标注可在“通用”中设置。

工具单键仍沿用原版默认值，例如 `P` 为画笔、`A` 为箭头、`L` 为直线、`R` 为圆角矩形。所有工具快捷键均可在“快捷键”页面修改。

## 本地构建

需要 macOS 14 或更高版本以及 Xcode。

```sh
xcodegen generate
xcodebuild -project Annotate.xcodeproj -scheme Annotate -configuration Debug build
```

也可以运行 Swift Package 测试：

```sh
swift test
```

定制版使用独立的 Bundle ID `com.siryeah.Annotate`，不会与官方版本共用应用身份。当前关闭了 Sparkle 自动更新，避免官方更新覆盖定制功能。

## 开源许可

项目基于 [epilande/Annotate](https://github.com/epilande/Annotate) 修改，继续遵循 MIT License。原作者版权与许可声明保留在 [LICENSE](LICENSE) 中。
