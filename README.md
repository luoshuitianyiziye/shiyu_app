# 时屿 · 日程笔记

> 一款集「每日任务 + 番茄专注 + 日历提醒 + 笔记」于一体的养成系效率 App。
> 完成任务获得经验，升级解锁九大段位插画，让自律像游戏一样有趣。

## ✨ 功能特性

- 🔐 **昵称登录**：无需注册，输入昵称即可开始
- ✅ **每日任务**：四象限分类 + 难度分级，完成任务获得经验
- 📈 **成长体系**：经验 → 等级 → 九大段位（雾芽 / 浅湾 / 青屿 / 竹林 / 松风 / 远山 / 星河 / 沧海 / 时屿），每升一段位解锁一张插画
- ⏰ **任务时段与提醒**：为任务设定时段，到点提醒；最晚未完成任务提醒
- 🍅 **番茄专注 + 白噪音**：25 分钟专注计时，内置雨声 / 海浪 / 篝火 / 风声，支持自定义上传白噪音
- 📅 **日历事件**：添加事件并设置提前提醒，支持倒数日
- 📝 **完整笔记**：富文本编辑器，支持文字 + 图片 + 待办清单
- 🎨 **莫兰迪主题**：清雅淡绿色系，支持浅色 / 深色切换

## 🛠 技术栈

| 技术 | 用途 |
|---|---|
| Flutter 3.47 / Dart 3.13 | 跨平台 UI 框架（Android / iOS / HarmonyOS） |
| Riverpod 2.x | 状态管理 |
| go_router | 页面路由导航 |
| drift (SQLite) | 本地数据库，8 张数据表 |
| flutter_local_notifications | 本地通知提醒 |
| just_audio | 白噪音播放 |
| flutter_quill | 富文本笔记编辑器 |
| image_picker + flutter_image_compress | 图片选择与压缩 |
| flutter_slidable | 左滑编辑 / 右滑完成手势 |
| shared_preferences | 轻量偏好存储 |

## 📁 项目结构

```
lib/
├── main.dart                 # 入口：主题加载、跨午夜定时器
├── app/                      # 应用级：路由、主题、公共组件、全局 Provider
├── core/                     # 核心：数据库(8表)、通知服务、反馈提示
└── features/                 # 功能模块（每个功能 = data 数据层 + presentation 界面层）
    ├── auth/                 # 昵称登录
    ├── today/                # 今日任务
    ├── focus/                # 番茄钟 + 白噪音
    ├── calendar/             # 日历事件
    ├── notes/                # 笔记
    ├── growth/               # 成长段位
    └── settings/             # 设置
```

## 🚀 运行项目

### 环境要求

- Flutter SDK 3.47+（[安装教程](https://flutter.cn/docs/get-started/install)）
- Android Studio 或任意支持 Flutter 的 IDE
- 真机或模拟器（Android / iOS）

### 步骤

```bash
# 1. 克隆项目
git clone <你的仓库地址>

# 2. 安装依赖
cd shiyu_app
flutter pub get

# 3. 运行
flutter run
```

### 打包 APK

```bash
# Debug 包
flutter build apk --debug

# Release 包（需要配置签名，见下文）
flutter build apk --release
```

> **关于签名**：仓库中的 `android/key.properties` 与 `*.jks` 已被 `.gitignore` 排除，不会随代码上传。正式发布请自行使用 `keytool` 生成签名密钥并配置。

## 🧪 测试

```bash
flutter analyze    # 静态检查
flutter test       # 单元测试 + 核心链路测试（12 项）
```

## 📖 技术文档

面向技术小白的完整项目讲解文档见 `docs/` 目录（含技术栈、目录结构、核心机制、关键代码解读、踩坑记录）。

## 📄 隐私说明

- 所有数据（任务、笔记、事件）均存储在**本地设备**，不上传任何服务器
- 白噪音与段位插画素材均为已获授权的原创 / 授权内容

## 📜 License

> 待你选择开源许可证（推荐 MIT / Apache-2.0），确定后在此补充并添加 LICENSE 文件。

---

**「时屿」** —— 把每一天过成一座岛，慢慢长出想要的自己。

## 🐳 AI 形象来源与许可

AI 助手「小屿」的形象（蓝发鲸鱼女仆）来自开源项目 **Coopanion**（AGPL-3.0-or-later）的 whale 形象包：

- 渲染器 `rig.js` / `body.js` / `figure.js` 以 **AGPL-3.0-or-later** 授权；
  本项目将其内联合并、精简为单文件页面 `assets/ai/whale/index.html`（IIFE 隔离作用域、
  模型与贴图内嵌 base64），修改后的合并代码同样以 AGPL-3.0-or-later 提供。
- 角色贴图：原设「溟月」（上善无形），DeepSeek 女仆装二创参考 ZipZipPipe；
  **贴图不在 Coopanion 的 AGPL 授权范围内**，围裙上的标志图形属于 DeepSeek、OpenAI、
  Anthropic、Google、阿里云、月之暗面、MiniMax 等公司；公开分发前请自行确认角色原设与商标权利。
- 详见 [`NOTICE.md`](NOTICE.md)。

若你公开分发包含该形象的本项目，请遵守 AGPL-3.0-or-later，并以同一许可开源整个应用。

## 🐳 AI 助手（形象 + 问答）

- **形象**：基于 Coopanion `whale` 形象包的 Live2D 渲染（WebView 内嵌自包含页面），
  支持 3 套皮肤（DeepSeek 蓝 / Harness 黑 / Claude 橙）、形象大小调节（0.6x~1.5x）、
  点击摸头/拖拽互动、思考/开心/难过表情联动。
- **问答**：与小屿聊天（保留最近对话上下文），回答可一键「转为任务」生成任务草案。
- **音效**：点击形象时的小黄鸭音效（可开关），来源见 `NOTICE.md`。
- 设置页「AI 助手 → 形象皮肤/大小/音效」可自定义。
