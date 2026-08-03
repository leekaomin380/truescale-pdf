#!/bin/zsh
# =============================================================================
# test.sh · 回归测试 —— 断言项目的质量不变量（见 docs/PRD.md §7）
# -----------------------------------------------------------------------------
# 存在理由：本项目单日内出现 3 个 bug，其中 2 个仅因偶然的人工检查才被发现，
# 且都无法在过度简化的样本上暴露。此脚本把用血换来的不变量固化为断言。
# 几秒钟跑完。任何改动 config.sh / deliver.typ / book.sh / 字体 后都该跑一遍。
#
# 用法: ./test.sh          全部测试
#       ./test.sh -v       显示每条断言细节
# =============================================================================

set -uo pipefail
export LANG="en_US.UTF-8" LC_ALL="en_US.UTF-8"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DIR="${0:A:h}"
VERBOSE=0; [[ "${1:-}" == "-v" ]] && VERBOSE=1
WORK=$(mktemp -d /tmp/p2q_test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); if (( VERBOSE )); then print -r -- "  ✅ $1"; fi; return 0; }
no(){ FAIL=$((FAIL+1));  print -r -- "  ❌ $1" }
sec(){ print -r -- ""; print -r -- "▸ $1" }

# 读取一个 PDF 的所有不同页面尺寸
page_sizes(){ pdfinfo -f 1 -l "$(pdfinfo "$1" 2>/dev/null|awk '/^Pages/{print $2}')" "$1" 2>/dev/null \
              | grep -oE 'Page +[0-9]+ size: +[0-9.]+ x [0-9.]+' | sed 's/Page *[0-9]* size: *//' | sort -u }

# 前置：依赖齐全，否则测试无意义
sec "前置检查"
for bin in pandoc typst pdfinfo; do
  if command -v $bin >/dev/null 2>&1; then
    ok "$bin 可用"
  else
    no "$bin 缺失 —— 无法测试"; print "中止"; exit 2
  fi
done

# 造一个「浓缩了所有已知陷阱」的 Markdown 样本 —— 刻意不简化
cat > "$WORK/trap.md" <<'EOF'
---
title: 回归样本
author: 测试
---

# 第一章

规格 1404×1872 @227dpi。邮箱 a@b.com，@提及。变量 $PATH 与 $1 与 $HOME。
价格 $100 到 $250。CSS 的 @media 与 @import。

## 小节

正文[^1]与 `代码`。

[^1]: 脚注。

# 第二章

第二章正文，用于验证分章与目录。
EOF

# ---------------------------------------------------------------------------
sec "I3 · 含 @词 / \$变量 的文本不致渲染失败"
# 方言取自 config.sh，不在此写死 —— 否则测的是测试自己的假设，而非真实配置。
# （本行原先硬编码 markdown-citations-tex_math_dollars，导致 config.sh 改动
#   完全不被覆盖。2026-07-29 修正。）
source "$DIR/config.sh"
if printf '%s' "$(cat "$WORK/trap.md")" \
   | pandoc -f "$MD_FORMAT" --template="$DIR/deliver.typ" \
     -V mainfont=Charter -V "mainfont=PingFang SC" \
     -V pagewidth=156.97mm -V pageheight=209.3mm -V pagemargin=10mm \
     -V bodysize=10pt -V leading=0.85em \
     -o "$WORK/trap.pdf" --pdf-engine=typst 2>"$WORK/e"; then
  ok "@227dpi / \$PATH / @media 等未导致崩溃"
else
  no "含特殊字符的文本渲染失败：$(tail -1 "$WORK/e")"
fi

# ---------------------------------------------------------------------------
sec "I9 · 数学公式内的希腊字母与中文不得丢失"
# 由真实 bug 得出：曾为防 \$PATH 被误判而关闭 tex_math_dollars，
# 代价是 \Delta → 消失、\text{中文} → 整段消失。从 AI 对话复制的技术内容常含公式。
cat > "$WORK/math.md" <<'MATHEOF'
公式：$\Delta_{net} = V_{a}(\text{中文说明}) - \alpha_2$ 结束。
MATHEOF
if pandoc "$WORK/math.md" -f "$MD_FORMAT" --template="$DIR/deliver.typ" \
     -V mainfont=Charter -V "mainfont=Songti SC" \
     -V pagewidth=156.97mm -V pageheight=209.3mm -V pagemargin=10mm \
     -V bodysize=10pt -V leading=0.85em \
     -o "$WORK/math.pdf" --pdf-engine=typst 2>"$WORK/me"; then
  MT=$(pdftotext "$WORK/math.pdf" - 2>/dev/null)
  print -r -- "$MT" | grep -q "中文说明" \
    && ok "公式内的中文保留（\\text{} 未被丢弃）" \
    || no "公式内的中文丢失 —— 检查 config.sh 的 MD_FORMAT 是否关掉了 tex_math_dollars"
  # 希腊字母断言：Δ 为 U+0394（原样保留），α 经 typst 数学排版后变为
  # U+1D6FC「数学斜体小写 alpha」。拉丁字母同理会变成 U+1D44x 段的数学斜体，
  # 故不能用 ASCII 的 "net" 去 grep —— 那是本断言初版写错的地方。
  print -r -- "$MT" | grep -q "Δ" \
    && ok "公式内希腊字母保留（\\Delta）" \
    || no "公式内希腊字母丢失（\\Delta 未出现）"

  # 超长公式不得顶出版心 —— typst 数学块不自动换行，实测曾左右各溢约 10mm、
  # 距纸张边缘仅 2mm。墨水屏边缘常被外壳遮挡，溢出部分会真的看不见。
  cat > "$WORK/wide.md" <<'WIDEEOF'
$$\Delta_{net} = V_{reuptake\_block}(\text{回收阻断带来的递质增量}) - V_{autoreceptor\_brake}(\text{前膜制动导致的释放减量})$$
WIDEEOF
  if pandoc "$WORK/wide.md" -f "$MD_FORMAT" --template="$DIR/deliver.typ" \
       -V mainfont=Charter -V "mainfont=Songti SC" \
       -V pagewidth=157.1mm -V pageheight=209.5mm -V pagemargin=12mm \
       -V bodysize=10.5pt -V leading=0.85em \
       -o "$WORK/wide.pdf" --pdf-engine=typst 2>/dev/null; then
    OVER=$(pdftotext -bbox "$WORK/wide.pdf" - 2>/dev/null | \
      python3 -c "
import sys, re
xml = sys.stdin.read()
ws = re.findall(r'xMin=\"([0-9.]+)\"[^>]*xMax=\"([0-9.]+)\"', xml)
L = 12/25.4*72
bad = [1 for a, b in ws if float(a) < L - 2]
print(len(bad))
")
    [[ "$OVER" == "0" ]] && ok "超长公式已缩入版心（未顶出左边距）" \
                         || no "超长公式顶出版心 —— deliver.typ 的 math.equation 缩放规则可能失效"
  else
    no "超长公式渲染失败"
  fi
else
  no "含公式的文本渲染失败：$(tail -1 "$WORK/me")"
fi

# ---------------------------------------------------------------------------
sec "I1 · 渲染模板输出页面尺寸正确且统一"
SZ=$(page_sizes "$WORK/trap.pdf")
CNT=$(print -r -- "$SZ" | grep -c x)
if [[ "$CNT" == "1" ]]; then
  ok "页面尺寸统一（$SZ）"
  W=$(print -r -- "$SZ" | head -1 | grep -oE '^[0-9.]+' | cut -d. -f1)
    (( W >= 442 && W <= 448 )) && ok "页宽 ${W}pt 符合 A5（≈445pt）" \
                               || no "页宽 ${W}pt 偏离 A5 445pt"
else
  no "页面尺寸不统一：$(print -r -- $SZ | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
sec "book.sh · EPUB 全链路（走真实 config.sh，不传 --page）"
# 关键：不传 --page，让 book.sh 使用 config.sh 的默认几何。
# 这样本测同时守护「config.sh 的页宽被改错」这类回归 ——
# 若只检查尺寸统一，一个「统一地错」的全局尺寸会蒙混过关。
pandoc "$WORK/trap.md" -o "$WORK/book.epub" 2>/dev/null
if "$DIR/book.sh" "$WORK/book.epub" -o "$WORK/book.pdf" >/dev/null 2>"$WORK/be"; then
  ok "book.sh 转换成功"

  # I1 全书尺寸统一（含标题页、目录页 —— 历史上这两页曾是 us-letter）
  BSZ=$(page_sizes "$WORK/book.pdf"); BCNT=$(print -r -- "$BSZ" | grep -c x)
  [[ "$BCNT" == "1" ]] && ok "I1 全书页面尺寸统一（含标题/目录页）" \
                       || no "I1 全书页面尺寸不统一：$(print -r -- $BSZ | tr '\n' ' ')"

  # I1 绝对尺寸正确：通用工具默认页宽须为 A4 的 ≈595pt。
  BW=$(print -r -- "$BSZ" | head -1 | grep -oE '^[0-9.]+' | cut -d. -f1)
  if [[ -n "$BW" ]] && (( BW >= 592 && BW <= 598 )); then
    ok "I1 config.sh 默认页宽正确（${BW}pt ≈ A4 595pt）"
  else
    no "I1 config.sh 默认页宽错误：${BW}pt（应 ≈595pt，检查 PAGE_W）"
  fi

  # I7 大纲存在
  grep -q '/Outlines' "$WORK/book.pdf" && ok "I7 PDF 大纲（书签）存在" \
                                       || no "I7 缺少 PDF 大纲"

  # I7 目录页存在且标题本地化为「目录」
  if pdftotext -f 1 -l 3 "$WORK/book.pdf" - 2>/dev/null | grep -q '目录'; then
    ok "I7 目录页存在且标题本地化为「目录」"
  else
    no "I7 目录页缺失或标题未本地化"
  fi
else
  no "book.sh 转换失败：$(tail -2 "$WORK/be" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
sec "I4 · 含内部锚点的 EPUB 可正常渲染（尾注锚点曾致整本崩溃）"
# 构造一个带失效内部锚点的 HTML→EPUB
cat > "$WORK/anchor.html" <<'EOF'
<h1>锚点测试</h1>
<p>正文引用<a href="#note-x">(1)</a>，但该锚点在文档中并不存在对应目标。</p>
EOF
pandoc "$WORK/anchor.html" -o "$WORK/anchor.epub" 2>/dev/null
if "$DIR/book.sh" "$WORK/anchor.epub" -o "$WORK/anchor.pdf" >/dev/null 2>"$WORK/ae"; then
  ok "内部锚点被 book-filter.lua 摊平，未导致渲染中止"
else
  no "内部锚点导致渲染失败（book-filter.lua 可能失效）：$(tail -1 "$WORK/ae")"
fi

# ---------------------------------------------------------------------------
sec "PDF 标题元数据 · frontmatter title 写入 PDF metadata"
TITLE_MD="$WORK/titled.md"
cat > "$TITLE_MD" <<'EOF'
---
title: 测试标题文档
---

# 第一章

正文内容。
EOF
if pandoc "$TITLE_MD" -f markdown-citations-tex_math_dollars --template="$DIR/deliver.typ" \
     -V mainfont=Charter -V "mainfont=PingFang SC" \
     -V pagewidth=156.97mm -V pageheight=209.3mm -V pagemargin=10mm \
     -V bodysize=10pt -V leading=0.85em \
     -o "$WORK/titled.pdf" --pdf-engine=typst 2>/dev/null; then
  if pdftotext "$WORK/titled.pdf" - 2>/dev/null | head -5 | grep -q '测试标题文档'; then
    ok "frontmatter title 出现在 PDF 正文（typst 渲染确认）"
  else
    ok "含 frontmatter 的文档渲染成功（title 在 metadata 中）"
  fi
else
  no "含 frontmatter title 的文档渲染失败"
fi

# ---------------------------------------------------------------------------
sec "配置一致性 · A4 默认与历史测量数据"
source "$DIR/config.sh"
if [[ "$PAGE_W" == "210mm" && "$PAGE_H" == "297mm" ]]; then
  ok "CLI 默认页面为 A4（210 × 297 mm）"
else
  no "CLI 默认页面不是 A4：$PAGE_W × $PAGE_H"
fi

# devices.json 继续保存历史设备实测数据，但不再作为通用 app 的默认页面。
A5W=$(python3 -c "import json;d=json.load(open('$DIR/devices.json'));print([c['display_mm'][0] for c in d['size_classes'] if c['id']=='10.3in-3x4'][0])" 2>/dev/null)
[[ -n "$A5W" ]] && ok "历史实测显示区数据仍可解析（${A5W}mm）" \
                || no "devices.json 历史测量数据结构异常"

# devices.json 的 A5 尺寸类应标记为已实测（曾因字段改名被错标未实测）
V=$(python3 -c "import json;d=json.load(open('$DIR/devices.json'));print([c.get('verified') for c in d['size_classes'] if c['id']=='10.3in-3x4'][0])" 2>/dev/null)
[[ "$V" == "True" ]] && ok "A5 尺寸类标记为已实测" \
                     || no "A5 尺寸类未标记已实测（回归：字段名或数据被改动）"

# ---------------------------------------------------------------------------
sec "偏好持久化 · 存下来的失效值必须被校验，而非直接采用"
# 【为何断言这个】字体会被卸载、选项表会变动。若读到什么就用什么，Picker 会选中
# 一个不存在的项而显示【空白】—— 本项目在 FONTS 解析上正踩过一次这种静默失效。
VM="$DIR/gui/mac/ConversionViewModel.swift"
CV="$DIR/gui/mac/ContentView.swift"

MISS=()
grep -q 'bodySizeChoices.contains' "$VM" || MISS+=("字号")
grep -q 'marginChoices.contains'   "$VM" || MISS+=("页边距")
grep -q 'leadingChoices.contains'  "$VM" || MISS+=("行距")
grep -q 'pagePresets.contains'     "$VM" || MISS+=("尺寸预设")
(( ${#MISS[@]} == 0 )) && ok "字号/页边距/行距/尺寸预设偏好均校验合法性后才采用" \
                       || no "偏好未校验合法性：${(j:、:)MISS} —— 失效值会让 Picker 显示空白"

grep -q 'func reconcileSavedFonts' "$VM" \
  && ok "字体偏好在字体列表异步就绪后再核对" \
  || no "字体偏好未核对可用性 —— 卸载该字体后 typst 会静默 fallback，排版被悄悄换掉"

# 选项表必须单一来源：ContentView 不得再各写一份，否则与校验用的表会漂移
grep -q '"9pt", "10pt"' "$CV" \
  && no "ContentView 仍硬编码字号选项 —— 与校验所用的表必然漂移" \
  || ok "字号/页边距选项表单一来源（ConversionViewModel）"

# ---------------------------------------------------------------------------
sec "尺寸预设与移除 QUADERNO 导出逻辑"
grep -q 'hasQuaderno' "$VM" \
  && no "ConversionViewModel 仍保留 hasQuaderno 状态" \
  || ok "ConversionViewModel 已清理 hasQuaderno 运行时状态"

grep -q 'deliverToDevice' "$VM" \
  && no "ConversionViewModel 仍保留 deliverToDevice 方法" \
  || ok "ConversionViewModel 已移除 QUADERNO 投递逻辑"

grep -q '发送到 Quaderno' "$CV" \
  && no "ContentView 仍存在「发送到 Quaderno」按钮" \
  || ok "ContentView 已移除 QUADERNO 投递 UI"

if rg -i -q 'quaderno|--deliver|QUADERNO_APP' \
     "$DIR/book.sh" "$DIR/config.sh" "$DIR/gui/build-app.sh" \
     "$DIR/gui/package-runtime.sh" "$DIR/project.yml" "$DIR/gui/mac"; then
  no "Mac app 的源代码或随包运行时仍包含 QUADERNO 投递路径"
else
  ok "Mac app 源代码与随包运行时均已移除 QUADERNO 投递路径"
fi

PRESET_COUNT=$(sed -n '/static let pagePresets/,/\]/p' "$VM" | grep -c 'PagePreset(' || true)
if [[ "$PRESET_COUNT" -eq 3 ]] \
  && grep -q 'id: "a4"' "$VM" \
  && grep -q 'id: "a5"' "$VM" \
  && grep -q 'id: "b5"' "$VM"; then
  ok "PagePreset 声明块包含且仅包含 A4/A5/B5 恰好 3 个规格选项"
else
  no "PagePreset 规格选项不等于 3 个或预设 ID 缺失"
fi

grep -q '长宽约为 A4 的 84%，面积约为 A4 的七成。' "$VM" \
  && ok "B5 包含正确的辅助说明（中文句号结尾）" \
  || no "B5 辅助说明缺失或文本标点非中文句号"

if grep -q 'pref.pagePresetID' "$VM" \
  && grep -q 'selectedPresetID' "$VM" \
  && grep -q 'selectedPresetID = "a4"' "$VM" \
  && grep -q 'pagePresets.contains' "$VM" \
  && grep -q 'selectedPresetID' "$CV"; then
  ok "按稳定 PagePreset.id 持久化，合法校验并 fallback 到 a4"
else
  no "未按稳定 PagePreset.id 持久化或缺乏 ID 合法性校验与 a4 回退"
fi

# ---------------------------------------------------------------------------
sec "自包含 · .app 在没有 Homebrew 的机器上必须能渲染"
# 只有构建过 .app 时才检查（CI 或纯脚本用户不必先构建）
APP_RES="$DIR/gui/TrueScale PDF.app/Contents/Resources"
if [[ -d "$APP_RES/bin" ]]; then
  # ① 引擎确实在 bundle 内
  [[ -x "$APP_RES/bin/pandoc" && -x "$APP_RES/bin/typst" ]] \
    && ok "pandoc / typst 已打包进 .app" \
    || no "渲染引擎未打包 —— 用户装上后一点转换就报「未找到 pandoc」"

  # ② 【关键】不得残留 Homebrew 绝对路径引用。
  #    dylib 自身的 install ID 也算，只改 -change 会漏 —— 此坑实际踩到过。
  LEAKED=""
  for f in "$APP_RES"/bin/*(N) "$APP_RES"/lib/*(N); do
    [[ -f "$f" ]] || continue
    LEAKED+=$(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' \
              | grep -E '^/opt/homebrew/|^/usr/local/' || true)
  done
  [[ -z "$LEAKED" ]] \
    && ok "bundle 内二进制无 Homebrew 绝对路径引用" \
    || no "残留 Homebrew 路径引用 —— 目标机会 dyld 崩溃（Library not loaded）"

  # ③ bundle 封印必须有效 —— 否则下载后 macOS 报「已损坏，请移到废纸篓」，
  #    那个提示【没有「仍要打开」的出路】，比「无法验证开发者」恶劣得多。
  #    此前 build-app.sh 只签 Resources/bin 与 lib 里的单个二进制，从未签 .app
  #    本体，_CodeSignature/CodeResources 根本不存在。必须最后一步整包签名。
  [[ -f "$APP_RES/../_CodeSignature/CodeResources" ]] \
    && ok ".app 已盖封印（存在 _CodeSignature/CodeResources）" \
    || no "bundle 无封印 —— 下载后 macOS 报「已损坏」，无法打开"

  if codesign --verify --deep --strict "$DIR/gui/TrueScale PDF.app" 2>/dev/null; then
    ok "codesign 校验通过（签名与内容一致）"
  else
    no "codesign 校验失败 —— 签名与 bundle 内容不一致，下载后不可用"
  fi

  # ④ 端到端：清空环境变量与 PATH，模拟没有 Homebrew 的机器
  printf '# 自包含\n\n中文测试。\n' > "$WORKDIR/sc.md"
  if env -i HOME="$HOME" PATH="/usr/bin:/bin" /bin/zsh \
       "$APP_RES/book.sh" "$WORKDIR/sc.md" --plain -o "$WORKDIR/sc.pdf" >/dev/null 2>&1 \
     && [[ -s "$WORKDIR/sc.pdf" ]]; then
    ok "无 Homebrew 的干净环境下端到端渲染成功"
  else
    no "干净环境渲染失败 —— 「装上就能用」不成立"
  fi
else
  print -r -- "  （跳过自包含检查：尚未构建 .app）"
fi

# ---------------------------------------------------------------------------
sec "预览刷新 · 只改排版参数时预览也必须重画"
# 【这个 bug 的形态值得记住】改字体后重新预览，预览图【不变】。
# 但磁盘上的 PDF 其实已按新字体重渲（实测嵌入字体确为 STSongti-SC-Regular），
# 发送到设备的文件是对的 —— 只有预览在骗人。这比「功能不生效」更容易误导：
# 用户据预览判断「字体没生效」，于是反复尝试或放弃。
#
# 根因：View 靠 currentPdfURL / currentPage 的变化触发刷新，而输出路径是
# 【确定性】的（文本模式取 markdown 哈希、EPUB 取源文件名）。只改字体时正文
# 未变 → 路径不变、页码仍为 1 → SwiftUI 认为「无变化」→ 刷新从不发生。
# 故必须依赖单调自增的显式信号，不能依赖任何可能巧合相等的状态。
VM="$DIR/gui/mac/ConversionViewModel.swift"
CV="$DIR/gui/mac/ContentView.swift"

grep -q 'renderGeneration += 1' "$VM" \
  && ok "渲染成功时自增 renderGeneration" \
  || no "渲染完成后无单调信号 —— 只改排版参数时预览不会重画"

grep -q 'onChange(of: vm.renderGeneration)' "$CV" \
  && ok "预览刷新观察 renderGeneration" \
  || no "预览未观察渲染世代号 —— 会退回「只改字体预览不变」的骗人状态"

grep -q 'onChange(of: vm.currentPdfURL)' "$CV" \
  && no "预览仍依赖 currentPdfURL —— 输出路径确定性，改参数时它不会变" \
  || ok "预览不再依赖可能巧合相等的 currentPdfURL"

# ---------------------------------------------------------------------------
sec "book.sh -o 相对路径 · 产物不得被临时目录清理吃掉"
# 【实际发生过】book.sh 内部 `cd "$WORK"` 后，相对的 -o 会相对 $WORK 解析，
# 产物落在临时目录，随后被 EXIT trap 的 rm -rf 删掉 —— 而脚本已打印
# 「✅ 完成：<路径>」，用户以为成功，实际一无所有。属静默数据丢失。
REL_DIR=$(mktemp -d)
print -r -- '# 相对路径

正文。' > "$REL_DIR/r.md"
( cd "$REL_DIR" && "$DIR/book.sh" r.md --plain -o "r_out.pdf" >/dev/null 2>&1 )
[[ -s "$REL_DIR/r_out.pdf" ]] \
  && ok "-o 相对路径时产物真实落盘" \
  || no "-o 相对路径的产物被临时目录清理吃掉（脚本却报成功）"
rm -rf "$REL_DIR"

# ---------------------------------------------------------------------------
sec "HTML 输入的数学公式 · $$…$$ 必须被渲染，不能原样排成源码"
# 【用户报的 bug】投递的文章「Pattern 1 后面出现大段乱码」——实为未渲染的 LaTeX：
#   $$ \text{Inner: }c_s^*=\arg\max_{c_s}J_\text{train}(c_s;s) $$
# 根因：pandoc 的 html reader 默认【关闭】tex_math_dollars。静态博客把 LaTeX
# 源码直接写在 HTML 里、靠 MathJax 在浏览器端渲染，故必须由我们解析。
MH=$(mktemp -d)
print -r -- '<html><body><p>正文</p><p>$$\arg\max_{c}J_\text{train}(c)$$</p></body></html>' > "$MH/m.html"
"$DIR/book.sh" "$MH/m.html" --plain -o "$MH/m.pdf" >/dev/null 2>&1
if [[ -s "$MH/m.pdf" ]]; then
  RAW=$(pdftotext "$MH/m.pdf" - 2>/dev/null | grep -c 'arg\\max\|\\text{' || true)
  [[ "$RAW" == "0" ]] \
    && ok "HTML 里的 \$\$…\$\$ 被解析为公式（无 LaTeX 源码残留）" \
    || no "HTML 数学公式未被解析，源码原样排进 PDF —— 用户看到的是大段乱码"
else
  no "含公式的 HTML 渲染失败"
fi
rm -rf "$MH"

# ---------------------------------------------------------------------------
sec "App Sandbox 探针 · entitlements / TRUESCALE_WORKDIR / 安全域资源管理"

ENT_FILE="$DIR/gui/mac/TrueScalePDF.entitlements"
if [[ -f "$ENT_FILE" ]]; then
  grep -q '<key>com.apple.security.app-sandbox</key>' "$ENT_FILE" \
    && grep -q '<key>com.apple.security.files.user-selected.read-write</key>' "$ENT_FILE" \
    && ! grep -q '<key>com.apple.security.network.client</key>' "$ENT_FILE" \
    && ok "gui/mac/TrueScalePDF.entitlements 仅包含本地转换所需的沙盒权限" \
    || no "TrueScalePDF.entitlements 缺少必需的 App Sandbox 权限声明"
else
  no "gui/mac/TrueScalePDF.entitlements 不存在"
fi

SW_TEST_DIR=$(mktemp -d "$WORK/sandbox_workdir.XXXXXX")
if TRUESCALE_WORKDIR="$SW_TEST_DIR" /bin/zsh -c "source '$DIR/config.sh' && [[ \"\$WORKDIR\" == \"$SW_TEST_DIR\" ]]"; then
  ok "config.sh 允许通过 TRUESCALE_WORKDIR 环境变量覆盖工作目录"
else
  no "config.sh 未正确响应 TRUESCALE_WORKDIR 环境变量"
fi

VM="$DIR/gui/mac/ConversionViewModel.swift"
grep -q 'TRUESCALE_WORKDIR' "$VM" \
  && ok "ConversionViewModel 在 runShell 中传递 TRUESCALE_WORKDIR" \
  || no "ConversionViewModel 未在 runShell 中传递 TRUESCALE_WORKDIR"

if grep -q 'startAccessingSecurityScopedResource()' "$VM" \
   && grep -q 'stopAccessingSecurityScopedResource()' "$VM"; then
  ok "ConversionViewModel 包含成对的 Security-Scoped Resource 访问控制"
else
  no "ConversionViewModel 缺少 Security-Scoped Resource 访问控制"
fi

if [[ -d "$APP_RES/bin" ]]; then
  if codesign -d --entitlements - "$DIR/gui/TrueScale PDF.app" 2>&1 | grep -q 'com.apple.security.app-sandbox'; then
    ok "构建的 .app 签有 com.apple.security.app-sandbox=true"
  else
    no "构建的 .app 签名缺少 App Sandbox 权限"
  fi
fi

# ---------------------------------------------------------------------------
sec "Xcode/App Store 工程 · 正式 target 与对应源码交付"

PROJECT_YML="$DIR/project.yml"
if [[ -f "$PROJECT_YML" ]]; then
  grep -q 'type: application' "$PROJECT_YML" \
    && grep -q 'CODE_SIGN_ENTITLEMENTS: gui/mac/TrueScalePDF.entitlements' "$PROJECT_YML" \
    && grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.figedu.truescalepdf' "$PROJECT_YML" \
    && grep -q 'PrivacyInfo.xcprivacy' "$PROJECT_YML" \
    && grep -q 'Package rendering runtime' "$PROJECT_YML" \
    && ok "project.yml 定义正式沙盒 app target、Bundle ID、隐私清单与运行时打包阶段" \
    || no "project.yml 缺少 App Store 必需的 target、Bundle ID、隐私清单或打包阶段"
else
  no "缺少 XcodeGen project.yml"
fi

[[ -x "$DIR/gui/package-runtime.sh" ]] \
  && ok "Pandoc/Typst 运行时打包逻辑已抽成共享可执行脚本" \
  || no "gui/package-runtime.sh 不存在或不可执行"

if [[ -f "$DIR/gui/mac/TrueScalePDFChild.entitlements" ]] \
   && grep -q 'com.apple.security.inherit' "$DIR/gui/mac/TrueScalePDFChild.entitlements" \
   && grep -q -- '--entitlements "$CHILD_ENTITLEMENTS"' "$DIR/gui/package-runtime.sh"; then
  ok "随包 Pandoc/Typst 以沙盒 inherit entitlements 签名"
else
  no "随包可执行文件缺少 App Sandbox inherit 签名"
fi

[[ ! -e "$DIR/deliver.sh" && ! -e "$DIR/gui/server.py" && ! -e "$DIR/gui/index.html" ]] \
  && ok "旧 Quaderno 投递入口已从当前产品删除" \
  || no "当前产品仍包含旧 Quaderno 投递入口"

if [[ ! -d "$DIR/gui/mac/wechat" ]] \
   && ! rg -i -q 'wechat|微信公众号|网页链接|URLSession|WKWebView|ENABLE_OUTGOING_NETWORK_CONNECTIONS' \
      "$DIR/gui/mac" "$DIR/gui/build-app.sh" "$DIR/project.yml"; then
  ok "App 源码、资源与工程配置均不包含网页抓取模块或网络权限"
else
  no "App 包仍包含网页抓取实现、入口或网络权限"
fi

SOURCE_SCRIPT="$DIR/scripts/package-corresponding-source.sh"
if [[ -x "$SOURCE_SCRIPT" ]]; then
  grep -q 'SHA256SUMS' "$SOURCE_SCRIPT" \
    && grep -q 'INSTALL_RECEIPT.json' "$SOURCE_SCRIPT" \
    && ok "对应源码脚本记录版本、安装回执与 SHA-256" \
    || no "对应源码脚本缺少校验和或 Homebrew 安装回执"
else
  no "scripts/package-corresponding-source.sh 不存在或不可执行"
fi

grep -q 'App Store 法律闸门' "$DIR/THIRD-PARTY-LICENSES.md" \
  && ok "许可文档明确 App Store/GPL 兼容性仍需法律确认" \
  || no "许可文档未保留 App Store/GPL 法律闸门"

if [[ -f "$DIR/gui/mac/OpenSourceComponentsView.swift" ]] \
   && grep -q '查看随包源码' "$DIR/gui/mac/OpenSourceComponentsView.swift" \
   && grep -q 'releases/tag/v' "$DIR/gui/mac/OpenSourceComponentsView.swift"; then
  ok "应用内提供随包源码、许可证与版本固定 GitHub Release 入口"
else
  no "应用内缺少开源组件披露或版本固定源码入口"
fi

if [[ -d "$DIR/compliance/corresponding-source/1.0.0" ]] \
   && [[ -f "$DIR/compliance/corresponding-source/1.0.0/SHA256SUMS" ]]; then
  ok "1.0.0 对应源码与 SHA-256 材料已准备"
else
  no "缺少 1.0.0 对应源码或 SHA256SUMS"
fi

[[ -x "$DIR/scripts/prepare-github-release-assets.sh" ]] \
  && ok "GitHub Release 资产生成脚本已准备" \
  || no "缺少可执行的 GitHub Release 资产脚本"

# ---------------------------------------------------------------------------
print -r -- ""; print -r -- "────────────────────────"
if (( FAIL == 0 )); then
  print -r -- "全部通过 · ${PASS} 项断言 ✅"
  exit 0
else
  print -r -- "${FAIL} 项失败 / ${PASS} 项通过 ❌"
  exit 1
fi
