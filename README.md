## 产品文档

首个面向个人用户版本的界面定义见 [docs/PRODUCT.md](docs/PRODUCT.md)，可复用组件拆解见 [docs/UI_COMPONENTS.md](docs/UI_COMPONENTS.md)。组件预览可在 Xcode 中打开 `RadioWave/Components/Previews/RadioComponentsPreview.swift` 的 Canvas 查看。

# RadioWave

RadioWave 是一个供个人使用的 macOS 网络电台客户端。电台目录来自 [Radio Browser](https://www.radio-browser.info/)，音频流由各电台提供。

## 功能

- 浏览并本地缓存 Radio Browser 中可用的电台，支持手动刷新。
- 按国家/地区、类型、语言、编码和最低码率筛选；支持搜索、排序和随机播放。
- 收藏电台，列表滚动时自动加载后续结果。
- 播放、暂停、调节音量和静音；上次选择的电台会在下次启动时恢复为暂停状态。
- 显示电台提供的当前曲目信息；播放器支持收藏当前电台。
- 保存播放历史中的打开时间和收听时长，并可据此计算播放次数、总时长和最近收听时间。
- 缓存电台图标，减少重复下载。

## 环境要求

- macOS 26.5 或更高版本
- Xcode 26.5 或兼容版本

项目使用 SwiftUI、AVFoundation 和系统 SQLite，无需额外的包管理器依赖。

## 构建和运行

1. 在 Xcode 中打开 `RadioWave.xcodeproj`。
2. 选择 `RadioWave` scheme 和本机 macOS 目标。
3. 点击 Run。

也可以在仓库根目录执行：

```sh
xcodebuild -project RadioWave.xcodeproj -scheme RadioWave -configuration Debug build
```

首次加载电台目录或播放网络电台需要网络连接。电台目录、图标和 ICY 元数据请求使用系统默认网络代理设置；音频流由 AVPlayer 处理，项目没有为它单独配置代理。

## 本地数据

应用启用了 macOS App Sandbox。数据位于当前用户的应用容器中：

```text
~/Library/Containers/com.logeable.RadioWave/Data/Library/Application Support/RadioWave/
├── station-cache.json       # Radio Browser 电台目录原始属性及缓存时间
├── play-history.sqlite      # 播放历史
└── station-icons/           # 按图标 URL 缓存的图片
```

收藏、当前电台和筛选条件保存在应用的 `UserDefaults` 中。

## 日志

应用日志同时写入 macOS 统一日志和文件：

```text
~/Library/Containers/com.logeable.RadioWave/Data/Library/Logs/RadioWave/RadioWave.log
```

达到 5 MB 后会轮转，上一份日志保留为 `RadioWave.log.1`。日志包括播放元数据来源、收到的原始曲目字符串和播放历史存储错误。实时查看文件日志：

```sh
tail -f "$HOME/Library/Containers/com.logeable.RadioWave/Data/Library/Logs/RadioWave/RadioWave.log"
```

## 项目结构

```text
RadioWave/
├── Models/       # 电台和播放历史模型
├── Services/     # Radio Browser API、ICY 元数据和日志
├── Storage/      # 电台缓存、图标缓存、收藏和播放历史存储
├── ViewModels/   # 电台库和播放器状态
└── Views/        # SwiftUI 界面
```
