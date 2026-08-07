# Epub 转 PDF

Epub 转 PDF 是一款专注的 macOS 转换工具，把 EPUB、HTML、FB2 和 Markdown 流式文档转换为固定版式 PDF。

它关注的不只是“能转成 PDF”，还关注页面的真实物理尺寸和排版稳定性。项目中的校准页、设备实测数据与回归测试用于验证页面映射、字号、边距和分页不会在转换过程中悄然漂移。

## 当前产品范围

- 输入：EPUB、HTML/HTM、FB2、Markdown
- 输出：PDF
- 页面规格：
  - A4（210 × 297 mm）— 常规打印纸
  - A5（148 × 210 mm）— A4 对折大小
  - B5（176 × 250 mm）— 比 A4 小一圈；长宽约为 A4 的 84%，面积约为 A4 的七成
- 排版：字体、字号、边距、行距、语言和生成时间可调
- 预览：转换前后都按目标页面比例展示
- 隐私：无账号、无遥测、无广告；文档和文本均在设备上处理，应用不访问互联网

Epub 转 PDF 不包含任何电子阅读器厂商的投递功能，也不要求安装 Quaderno 或其他设备客户端。生成的 PDF 可由用户自行保存、打印或传输到任意支持 PDF 的设备。

## 安装与构建

### 使用 Xcode

要求 macOS 14、Apple Silicon Mac、Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen pandoc typst
xcodegen generate
open TrueScalePDF.xcodeproj
```

Release 构建会把 Pandoc、Typst 和 GNU MP 打包进 App，因此最终用户无需安装 Homebrew。

### 命令行转换

```bash
brew install pandoc typst
./book.sh book.epub -o book.pdf
./book.sh article.md --page 148mm 210mm -o article-a5.pdf
```

运行 `./book.sh --help` 查看可调参数。MOBI/AZW 是可选路径，需要用户另行安装 Calibre；Mac App Store 版本当前不把 Calibre 打包进应用。

## 验证

```bash
./test.sh
```

测试覆盖 EPUB 转换、页面尺寸、输入安全处理、偏好恢复、原生 App 中 Quaderno 路径的移除，以及自包含运行时。

## 开源组件与对应源码

本项目自身以 MIT 许可发布。App 内包含 Pandoc、Typst 和 GNU MP；第三方许可、二进制改动和对应源码提供方式见 [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)。

每个发布版本都会同时提供：

- App 内的许可证全文和对应源码目录
- 同版本 GitHub Release 中的对应源码归档与 SHA-256 校验值
- 用于复制、重定位和签名这些组件的构建脚本

### 本地 HTML 转换边界

- 按标题、段落、列表、表格等文档结构重新排版，不是网页截图。
- 支持引用同目录及子目录中的本地图片。
- 不执行 JavaScript，也不访问互联网或上传文档。
- 依赖复杂 CSS 或 JavaScript 的动态网页不会保持浏览器中的像素级外观。

源码归档由以下命令生成：

```bash
./scripts/package-corresponding-source.sh compliance/corresponding-source/1.1.0
./scripts/prepare-github-release-assets.sh
```

## 精度基准与历史资料

项目最初通过 QUADERNO A5 做了 1:1 物理尺寸实测。设备名称仅用于说明测量样本，不代表当前产品依赖该设备或与厂商存在关联：

- [电子墨水设备显示区物理尺寸测定法](docs/quaderno-display-metrics.md)
- [电子墨水排版研究](docs/typography-for-eink.md)
- [历史 PRD](docs/PRD.md)

`docs/development-log-zh.md`、`docs/website-architecture.txt` 和早期任务文档记录旧版 Quaderno 投递原型，仅作为工程沿革保留，不代表当前产品功能。

## 支持与隐私

- [隐私政策](PRIVACY.md)
- [支持与联系](SUPPORT.md)
- [安全问题报告](SECURITY.md)

## 法律说明

用户应只转换自己有权访问和使用的内容。应用不会绕过 DRM 或其他访问控制；著作权与内容再分发责任仍由用户判断。

Epub 转 PDF 与 Fujitsu 或其他阅读器厂商不存在隶属、赞助或背书关系。QUADERNO 是其权利人的商标，仅在历史测量资料中作事实性指称。
