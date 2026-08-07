# 第三方组件与许可

本项目自身以 MIT 许可发布（见 [LICENSE](LICENSE)）。

为让 macOS 应用「装上即可用、无需先安装 Homebrew」，发布的 `.app` **内含**下列
第三方可执行文件与动态库。它们各自的许可与本项目的 MIT 许可**互不改变**：
应用通过启动独立进程调用它们，未在代码层链接，属 GPL 意义上的 mere aggregation。

分发这些二进制会触发相应义务，下面逐项说明如何履行。

---

## 组件清单

| 组件 | 版本 | 许可 | 在 `.app` 中的位置 |
|---|---|---|---|
| [pandoc](https://github.com/jgm/pandoc) | 3.10 | GPL-2.0-or-later | `Contents/Resources/bin/pandoc` |
| [typst](https://github.com/typst/typst) | 0.15.1 | Apache-2.0 | `Contents/Resources/bin/typst` |
| [GNU MP (libgmp)](https://gmplib.org/) | 6.x | LGPL-3.0-or-later **或** GPL-2.0-or-later | `Contents/Resources/lib/libgmp.10.dylib` |

许可全文随 `.app` 一同分发，位于 `Contents/Resources/licenses/`。

未打包、作为**可选**外部依赖的组件（仅 mobi/azw 转换需要）：

| 组件 | 许可 | 说明 |
|---|---|---|
| [Calibre](https://calibre-ebook.com/) 的 `ebook-convert` | GPL-3.0 | 是完整应用、数百 MB，不打包；缺失时仅 mobi/azw 不可用，其余格式不受影响 |

---

## 对二进制所做的改动

必须如实声明：**pandoc 的二进制被修改过**，但仅限于加载路径，程序逻辑未变。

1. **重定位动态库引用**（`install_name_tool -change`）
   pandoc 原本以绝对路径 `/opt/homebrew/opt/gmp/lib/libgmp.10.dylib` 引用 libgmp。
   在没有 Homebrew 的机器上该路径不存在，应用会在启动时 dyld 崩溃。
   故改写为 `@executable_path/../lib/libgmp.10.dylib`，指向 `.app` 内自带的副本。
   libgmp 自身的 install ID 同样被改写（`install_name_tool -id`）。

2. **重新签名**
   改动 Mach-O 会使原签名失效，未重签的二进制会被 macOS 直接终止。
   本地调试构建使用 ad-hoc 签名；App Store 归档则使用 Xcode 提供的发布
   签名身份。Pandoc 和 Typst 携带 `com.apple.security.app-sandbox` 与
   `com.apple.security.inherit` 权限，作为沙盒 App 的子进程运行；动态库不携带
   可执行文件权限。

上述改动**不涉及源代码**，二者均由 [`gui/build-app.sh`](gui/build-app.sh) 自动完成，
过程完全可复现、可审计。

---

## 如何获取对应源码（履行 GPL 义务）

pandoc 与 libgmp 均以未经源码修改的形式分发，其完整源码可从上游取得：

- **pandoc 3.10** — <https://github.com/jgm/pandoc/releases/tag/3.10>
- **GNU MP** — <https://gmplib.org/download/gmp/>（版本号见 `.app` 内
  `Contents/Resources/lib/libgmp.10.dylib` 或 `brew info gmp`）

本项目使用的二进制来自 Homebrew，其构建配方（同样公开、可复现）见：

- <https://github.com/Homebrew/homebrew-core/blob/master/Formula/p/pandoc.rb>
- <https://github.com/Homebrew/homebrew-core/blob/master/Formula/g/gmp.rb>

每个候选发布版本必须显式运行：

```bash
./scripts/package-corresponding-source.sh
```

脚本会根据构建机上实际打包的 pandoc 与 GNU MP 版本下载上游源码，保存 Homebrew
安装回执、二进制重定位/打包脚本，并为全部材料生成 `SHA256SUMS` 与版本清单。
生成的目录必须与对应 app 二进制在同一下载位置持续提供；仅保留上游链接不能替代
我们自己提供对应源码的责任。

> **App Store 法律闸门：**提供许可全文和对应源码是必要条件，但不当然解决 GPL/LGPL
> 与 Apple 标准分发条款、签名及 DRM 的兼容性问题。提交 Mac App Store 前仍需由熟悉
> 开源许可与 Apple 分发条款的律师确认；若无法取得肯定结论，应改用不捆绑 Pandoc 的
> 架构或改走站外公证分发。

---

## 架构限制（与许可无关，但同属分发须知）

打包进 `.app` 的引擎均为 **arm64（Apple Silicon）**。

因此发布的 `.app` **仅适用于 Apple Silicon Mac**（M1 及更新机型）。
Intel Mac 用户需自行从源码构建（`./gui/build-app.sh`，构建机需先
`brew install pandoc typst`，会自动打包该机器架构的二进制）。

判断自己的机型：菜单 →「关于本机」，芯片一栏若为 Apple M 系列即可使用。
