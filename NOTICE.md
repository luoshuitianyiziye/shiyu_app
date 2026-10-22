# 第三方组件与许可声明

## AI 助手形象（whale / 蓝发鲸鱼女仆「溟月」）

- **来源**：开源项目 **Coopanion**（AGPL-3.0-or-later）中的
  `packages/cortico-world-desktop-pet/web/whale/`（形象包）、`web/kit/`（rig.js / body.js 渲染器）。
- **代码许可**：AGPL-3.0-or-later。本项目将其 JS 内联合并、精简为单文件页面
  （`assets/ai/whale/index.html`），并做了以下修改：去除模块导入/导出、以 IIFE 隔离作用域、
  将 model.json 与全部贴图内嵌（base64）、增加与 Flutter 的桥接接口。
  按 AGPL-3.0 第 5 条，本文件与 `assets/ai/whale/index.html` 中的合并代码同样以
  AGPL-3.0-or-later 提供；若本项目整体公开分发，需要以 AGPL-3.0-or-later 开源整个应用。
- **角色贴图**：角色原设「溟月」（上善无形）；DeepSeek 女仆装二创参考 ZipZipPipe。
  Coopanion 的 THIRD_PARTY_NOTICES 明确说明：`web/whale/` 的贴图**不在**其 AGPL 授权范围内，
  「想在别处使用请自行确认原设与各家标志的权利」。围裙上的标志图形属于 DeepSeek、OpenAI、
  Anthropic、Google、阿里云、月之暗面、MiniMax 等公司。
  本项目使用者需自行确认角色原设与商标的使用权利后再公开分发。

## 其他第三方组件

- Flutter / Dart 生态依赖见 `pubspec.yaml` 与 `pubspec.lock`（各包自带许可）。
- 字体、图标：Flutter 内置 Material Icons；无额外字体资产。
