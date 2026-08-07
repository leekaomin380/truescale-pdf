import Foundation
import AppKit
import PDFKit

struct SupportedFileFormat {
    let extensions: [String]
    let typeName: String

    static let all: [SupportedFileFormat] = [
        SupportedFileFormat(extensions: ["epub"], typeName: "EPUB 电子书"),
        SupportedFileFormat(extensions: ["html", "htm"], typeName: "HTML 文档"),
        SupportedFileFormat(extensions: ["fb2"], typeName: "FB2 电子书"),
        SupportedFileFormat(extensions: ["md", "markdown"], typeName: "Markdown 文档")
    ]

    static var allowedExtensions: [String] {
        all.flatMap { $0.extensions }
    }

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return allowedExtensions.contains(ext)
    }

    static func typeName(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return all.first(where: { $0.extensions.contains(ext) })?.typeName
    }
}

struct PagePreset: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let dimensionsLabel: String
    let widthMm: Double
    let heightMm: Double
    let secondaryExplanation: String?

    var pageW: String { "\(String(format: "%.1f", widthMm))mm" }
    var pageH: String { "\(String(format: "%.1f", heightMm))mm" }

    var displayName: String {
        "\(name) — \(dimensionsLabel)"
    }
}

struct ConfigDefaults {
    var pageW = "210.0mm"
    var pageH = "297.0mm"
    var margin = "10mm"
    var bodySize = "10pt"
    var leading = "0.85em"
    var docLang = "zh"
    var fonts: [String] = ["Helvetica Neue", "PingFang SC"]
}

struct RenderMetrics {
    var pages = 0
    var pageSizes: [String] = []
    var sizeUniform = true
    var measureMm: Double = 0
    var cjkPerLine = 0
    var latinPerLine = 0
    var cjkVerdict = ""
    var latinVerdict = ""
}

class ConversionViewModel: ObservableObject {
    let repoURL: URL

    static let pagePresets: [PagePreset] = [
        PagePreset(
            id: "a4",
            name: "A4 · 常规打印纸",
            dimensionsLabel: "210 × 297 mm",
            widthMm: 210.0,
            heightMm: 297.0,
            secondaryExplanation: nil
        ),
        PagePreset(
            id: "a5",
            name: "A5 · A4 对折大小",
            dimensionsLabel: "148 × 210 mm",
            widthMm: 148.0,
            heightMm: 210.0,
            secondaryExplanation: nil
        ),
        PagePreset(
            id: "b5",
            name: "B5 · 比 A4 小一圈",
            dimensionsLabel: "176 × 250 mm",
            widthMm: 176.0,
            heightMm: 250.0,
            secondaryExplanation: "长宽约为 A4 的 84%，面积约为 A4 的七成。"
        )
    ]

    @Published var selectedPresetID: String = "a4" {
        didSet {
            let p = selectedPreset
            config.pageW = p.pageW
            config.pageH = p.pageH
        }
    }

    var selectedPreset: PagePreset {
        Self.pagePresets.first(where: { $0.id == selectedPresetID }) ?? Self.pagePresets[0]
    }

    @Published var config = ConfigDefaults()
    @Published var cjkFonts: [String] = []
    @Published var latinFonts: [String] = []
    @Published var selectedCjkFont = "PingFang SC"
    @Published var selectedLatinFont = "Helvetica Neue"
    @Published var bodySize = "10pt"
    @Published var margin = "10mm"
    @Published var leading = "0.85em"
    @Published var docLang = "zh"
    @Published var printTime = true
    @Published var statusMessage = ""
    @Published var statusKind: StatusKind = .info
    @Published var isConverting = false

    @Published var currentPdfURL: URL?
    @Published var totalPages = 0
    @Published var currentPage = 1
    @Published var renderMetrics: RenderMetrics?

    // Local file input
    @Published var sourceFileURL: URL?
    @Published var sourceFileName = ""

    var sourceFileTypeDisplayName: String? {
        guard let url = sourceFileURL else { return nil }
        return SupportedFileFormat.typeName(for: url)
    }

    @discardableResult
    func selectSourceFile(url: URL) -> Bool {
        guard SupportedFileFormat.isSupported(url: url) else {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())"
            setStatus("暂不支持 \(ext) 文件\n支持 EPUB、HTML、FB2 和 Markdown", .err)
            return false
        }
        sourceFileURL = url
        sourceFileName = url.lastPathComponent
        return true
    }

    func clearSourceFile() {
        sourceFileURL = nil
        sourceFileName = ""
        currentPdfURL = nil
        totalPages = 0
        renderMetrics = nil
    }

    enum StatusKind { case info, ok, err, run }

    /// 字号与页边距的可选值。
    /// 【为何放在这里】原先硬编码在 ContentView 的 ForEach 里，而偏好校验需要
    /// 判断"存下来的值是否仍是合法选项"，两处各写一份必然漂移。故收拢为单一来源。
    static let bodySizeChoices = ["9pt", "10pt", "10.5pt", "11pt", "11.5pt", "12pt", "13pt", "14pt"]
    static let marginChoices   = ["8mm", "10mm", "12mm", "14mm", "16mm"]

    /// 行距选项：(内部 em 值, 界面显示的传统倍行距)。
    /// typst 的 leading 是「行间额外空隙」，人们说的「1.5 倍行距」是「基线距 ÷ 字号」，
    /// 二者差一个字身高。实测换算为线性关系：倍数 = em + 0.7。
    /// 界面只显示右侧，em 不外露 —— 显示 0.85 会让人误以为是 0.85 倍，实际是 1.55 倍。
    static let leadingChoices: [(String, String)] = [
        ("0.7em",  "1.4 倍"),
        ("0.8em",  "1.5 倍"),
        ("0.85em", "1.55 倍"),
        ("0.9em",  "1.6 倍"),
        ("1.0em",  "1.7 倍"),
    ]

    /// 上次渲染所依据的输入指纹（内容 + 全部排版参数）。
    ///
    /// 【为什么需要它】此前另存的唯一条件是「currentPdfURL != nil」，即
    /// 只要曾渲染过任何东西按钮就一直可用，完全不校验当前输入是否对应那个 PDF。
    /// 后果：换一本 EPUB 后不点预览直接另存，可能存出去的是【上一本】。
    ///
    /// 现改为「另存自行保证正确」：比对指纹，不一致就先重渲再执行 ——
    /// 这样按钮名义与实际行为一致，用户不必记住「必须先预览」这条前置规则。
    private var renderedFingerprint: String?

    /// 当前输入的指纹。任何影响产物的东西都必须计入。
    private func currentFingerprint() -> String {
        let source = sourceFileURL?.path ?? ""
        return [
            source,
            bodySize, margin, leading, docLang,
            selectedLatinFont, selectedCjkFont,
            config.pageW, config.pageH,
            String(printTime)
        ].joined(separator: "\u{1F}")
    }

    /// 产物是否已与当前输入脱节。
    var isStale: Bool {
        currentPdfURL == nil || renderedFingerprint != currentFingerprint()
    }

    /// 渲染世代号 —— 每次渲染成功后自增，供 View 触发预览刷新。
    ///
    /// 【为何必须有它】View 原先靠 `currentPdfURL` 与 `currentPage` 的变化来刷新预览。
    /// 但输出路径是【确定性】的（EPUB 模式取源文件名），
    /// 只改字体/字号/行距时正文未变，路径与页码都不变 —— SwiftUI 的 onChange 认为
    /// 「没有变化」，于是 updatePreview 从不被调用，预览停留在上一次渲染。
    ///
    /// 后果很坏：磁盘上的 PDF 已按新参数重渲（实测确认嵌入字体已换成
    /// STSongti-SC-Regular），保存的文件是对的，**只有预览在骗人**。
    /// 用户据此判断「字体没生效」，实际生效了 —— 比不生效更容易误导。
    ///
    /// 故不再依赖任何可能巧合相等的状态，改用单调自增的显式信号。
    @Published private(set) var renderGeneration = 0

    /// 记录本次渲染对应的输入 —— 渲染成功后调用。
    /// EPUB 渲染成功后在这里更新指纹与世代号，保证预览刷新。
    func markRendered() {
        renderedFingerprint = currentFingerprint()
        renderGeneration += 1
    }

    /// 等待渲染完成的回调。渲染是异步的，ensureFresh 需要在它结束后才继续。
    private var pendingRenderCallbacks: [(Bool) -> Void] = []

    /// 渲染流程结束时统一收敛 —— 成功与失败都必须调用，否则等待者永远悬着。
    private func finishPendingRender(success: Bool) {
        let cbs = pendingRenderCallbacks
        pendingRenderCallbacks = []
        cbs.forEach { $0(success) }
    }

    /// 触发 EPUB 渲染流程。
    private func renderCurrentInput(_ done: @escaping (Bool) -> Void) {
        pendingRenderCallbacks.append(done)
        convertEpub()
    }

    /// 确保产物与当前输入一致；若已脱节则重新渲染，完成后执行 next。
    /// 这是「另存自行保证正确」的入口。
    func ensureFresh(then next: @escaping () -> Void) {
        guard isStale else { next(); return }
        setStatus("内容有变，正在重新渲染…", .run)
        renderCurrentInput { ok in
            guard ok else { return }   // 失败时状态已由渲染流程写明
            next()
        }
    }

    init() {
        if let resourceURL = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("book.sh").path) {
            repoURL = resourceURL
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("book.sh").path) {
                repoURL = cwd
            } else {
                repoURL = cwd.deletingLastPathComponent()
            }
        }

        // File I/O only — fast, safe on main thread
        loadConfig()

        // Populate font lists with config defaults so pickers are immediately usable
        if !config.fonts.isEmpty { latinFonts = [config.fonts[0]] }
        if config.fonts.count >= 2 { cjkFonts = [config.fonts[1]] }

        // Shell calls block — defer to background to avoid SwiftUI layout crash
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fonts = self.listFontsAsync()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cjkFonts = fonts.cjk
                self.latinFonts = fonts.latin
                self.reconcileSavedFonts()
            }
        }
    }

    // MARK: - Config

    private func loadConfig() {
        let configPath = repoURL.appendingPathComponent("config.sh")
        guard let text = try? String(contentsOf: configPath, encoding: .utf8) else {
            applySavedPreferences()
            return
        }
        func grab(_ key: String, _ def: String = "") -> String {
            let pattern = #"^"# + key + #"="([^"]*)""#
            guard let range = text.range(of: pattern, options: .regularExpression) else { return def }
            return String(text[range]).replacingOccurrences(of: "\(key)=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        config.margin = grab("PAGE_MARGIN", "10mm")
        config.bodySize = grab("BODY_SIZE", "10pt")
        config.leading = grab("LEADING", "0.85em")
        config.docLang = grab("DOC_LANG", "zh")

        let fontPattern = #"FONTS=\(([^)]*)\)"#
        if let range = text.range(of: fontPattern, options: .regularExpression) {
            let fontStr = String(text[range])
            config.fonts = fontStr.components(separatedBy: "\"")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                // 按引号分割会产生字体之间的分隔片段（如 " "）——必须 trim 后再判空，
                // 否则那个空格会被当成一个字体名，导致 Picker 选中一个不存在的项而显示空白。
                .filter { !$0.isEmpty && $0 != "FONTS=(" && $0 != ")" }
        }

        // config.sh 是【出厂默认】；用户调过的值优先。
        // 之前没有任何持久化，字体字号每次启动都被打回默认 —— 而这些参数
        // 恰恰是一次性调好、长期不变的东西，每次重设是纯粹的摩擦。
        bodySize = config.bodySize
        margin = config.margin
        leading = config.leading
        docLang = config.docLang
        if config.fonts.count >= 2 {
            selectedLatinFont = config.fonts[0]
            selectedCjkFont = config.fonts[1]
        }

        let p = selectedPreset
        config.pageW = p.pageW
        config.pageH = p.pageH

        applySavedPreferences()
    }

    // MARK: - 偏好持久化

    /// UserDefaults 键。加前缀避免与系统或将来的键冲突。
    private enum PrefKey {
        static let cjkFont      = "pref.cjkFont"
        static let latinFont    = "pref.latinFont"
        static let bodySize     = "pref.bodySize"
        static let margin       = "pref.margin"
        static let leading      = "pref.leading"
        static let pagePresetID = "pref.pagePresetID"
    }

    /// 用已保存的偏好覆盖出厂默认值。
    ///
    /// 【为何不直接信任存下来的值】字体可能被卸载、pagePresets 选项列表可能变化。
    /// 存的值若已失效就必须回退到默认，否则 Picker 会选中一个不存在的项而显示空白 ——
    /// 这个坑本项目踩过一次（FONTS 解析出空字符串，导致中文字体下拉整个空掉）。
    /// 故所有值取用前都要校验。
    private func applySavedPreferences() {
        let d = UserDefaults.standard
        // 字号/边距/行距：只接受仍在选项表里的值
        if let v = d.string(forKey: PrefKey.bodySize),
           Self.bodySizeChoices.contains(v) { bodySize = v }
        if let v = d.string(forKey: PrefKey.margin),
           Self.marginChoices.contains(v) { margin = v }
        if let v = d.string(forKey: PrefKey.leading),
           Self.leadingChoices.contains(where: { $0.0 == v }) { leading = v }
        // 字体：能否使用要等字体列表异步加载完才知道，故此处先存起来，
        // 由 reconcileSavedFonts() 在列表就绪后再校验。
        if let v = d.string(forKey: PrefKey.cjkFont)   { selectedCjkFont = v }
        if let v = d.string(forKey: PrefKey.latinFont) { selectedLatinFont = v }

        // 页面尺寸预设：基于稳定 PagePreset.id 校验与持久化
        if let savedID = d.string(forKey: PrefKey.pagePresetID),
           Self.pagePresets.contains(where: { $0.id == savedID }) {
            selectedPresetID = savedID
        } else {
            selectedPresetID = "a4"
        }
        let p = selectedPreset
        config.pageW = p.pageW
        config.pageH = p.pageH
    }

    /// 字体列表异步就绪后，核对已保存的字体是否真的可用；不可用则回退到出厂默认。
    private func reconcileSavedFonts() {
        if !cjkFonts.isEmpty, !cjkFonts.contains(selectedCjkFont) {
            selectedCjkFont = config.fonts.count >= 2 ? config.fonts[1] : cjkFonts[0]
        }
        if !latinFonts.isEmpty, !latinFonts.contains(selectedLatinFont) {
            selectedLatinFont = config.fonts.first ?? latinFonts[0]
        }
    }

    /// 保存当前偏好。由 View 在参数变化时调用。
    func savePreferences() {
        let d = UserDefaults.standard
        d.set(selectedCjkFont,     forKey: PrefKey.cjkFont)
        d.set(selectedLatinFont,   forKey: PrefKey.latinFont)
        d.set(bodySize,            forKey: PrefKey.bodySize)
        d.set(margin,              forKey: PrefKey.margin)
        d.set(leading,             forKey: PrefKey.leading)
        d.set(selectedPresetID,    forKey: PrefKey.pagePresetID)
    }

    private func listFontsAsync() -> (cjk: [String], latin: [String]) {
        let result = runShell(["typst", "fonts"])
        guard result.exitCode == 0 else {
            return (
                ["PingFang SC", "Songti SC", "Heiti SC", "Microsoft YaHei", "SimSun"],
                ["Helvetica Neue", "Charter", "Georgia", "Times New Roman", "Calibri"]
            )
        }
        let allFonts = Set(result.stdout.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })

        let cjkPref = ["PingFang SC", "Songti SC", "Heiti SC", "STSong",
                        "Hiragino Sans GB", "Noto Serif CJK SC",
                        "Source Han Sans SC", "Source Han Serif SC",
                        "Microsoft YaHei", "SimSun"]
        let latinPref = ["Charter", "Iowan Old Style", "Georgia", "Palatino",
                         "Times New Roman", "Helvetica Neue", "Arial", "Avenir Next",
                         "Calibri"]

        let cjk = cjkPref.filter { allFonts.contains($0) }
        let latin = latinPref.filter { allFonts.contains($0) }
        return (
            cjk.isEmpty ? ["PingFang SC"] : cjk,
            latin.isEmpty ? ["Helvetica Neue"] : latin
        )
    }

    // MARK: - Metrics

    func computeMetrics(pages: Int? = nil, pageSizes: [String]? = nil) -> RenderMetrics {
        let pageWmm = Double(config.pageW.replacingOccurrences(of: "mm", with: "")) ?? 210.0
        let marginMm = Double(margin.replacingOccurrences(of: "mm", with: "")) ?? 10
        let sizePt = Double(bodySize.replacingOccurrences(of: "pt", with: "")) ?? 10
        let measure = pageWmm - 2 * marginMm
        let sizeMm = sizePt * 25.4 / 72
        let cjk = Int(round(measure / sizeMm))
        let lat = Int(round(measure / (sizeMm * 0.5)))

        var m = RenderMetrics()
        m.measureMm = measure
        m.cjkPerLine = cjk
        m.latinPerLine = lat
        m.cjkVerdict = cjk > 45 ? "偏密" : cjk > 40 ? "偏长" : cjk >= 28 ? "合适" : "偏短"
        m.latinVerdict = lat > 75 ? "偏长" : lat >= 45 ? "合适" : "偏短"
        if let p = pages { m.pages = p }
        if let s = pageSizes {
            m.pageSizes = s
            m.sizeUniform = s.count <= 1
        }
        return m
    }

    // MARK: - Convert

    func convertEpub() {
        guard let src = sourceFileURL else {
            setStatus("请先选择 EPUB 文件", .err)
            return
        }
        setStatus("渲染中…", .run)
        isConverting = true

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let accessing = src.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    src.stopAccessingSecurityScopedResource()
                }
            }

            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("p2q_app")
            try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let outPdf = workDir.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".pdf")

            let result = runShell([
                repoURL.appendingPathComponent("book.sh").path,
                src.path, "-o", outPdf.path,
                "--size", bodySize, "--margin", margin,
                "--leading", leading, "--lang", docLang,
                "--font", "\(selectedLatinFont),\(selectedCjkFont)",
                "--page", config.pageW, config.pageH,
                printTime ? "--time" : "--no-time"
            ])

            DispatchQueue.main.async { [self] in
                isConverting = false
                if result.exitCode != 0 {
                    let cleanErr = Self.parseErrorMessage(result.stderr)
                    setStatus("渲染失败：\(cleanErr)", .err)
                    self.finishPendingRender(success: false)
                    return
                }

                self.currentPdfURL = outPdf
                let info = PDFDocument(url: outPdf)
                self.totalPages = info?.pageCount ?? 0
                self.currentPage = 1
                let sizes = getPageSizes(pdf: outPdf, pages: self.totalPages)
                self.renderMetrics = computeMetrics(pages: self.totalPages, pageSizes: sizes)
                setStatus("渲染完成，共 \(self.totalPages) 页", .ok)
                self.markRendered()
                self.finishPendingRender(success: true)
            }
        }
    }

    // MARK: - Preview

    func renderPage(_ page: Int, dpi: Int = 110) -> NSImage? {
        guard let pdfURL = currentPdfURL,
              let pdfDoc = PDFDocument(url: pdfURL),
              let pdfPage = pdfDoc.page(at: page - 1) else { return nil }

        let scale = CGFloat(dpi) / 72.0
        let rect = pdfPage.bounds(for: .mediaBox)
        let size = NSSize(width: rect.width * scale, height: rect.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .high
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.scaleBy(x: scale, y: scale)
            pdfPage.draw(with: .mediaBox, to: ctx)
        }
        image.unlockFocus()
        return image
    }

    // MARK: - Save PDF

    func savePDF() {
        guard let pdfURL = currentPdfURL else {
            setStatus("无可保存的内容", .err)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceFileName.isEmpty
            ? "converted.pdf"
            : sourceFileName.replacingOccurrences(of: #"^(.+)\.[^.]+$"#, with: "$1", options: .regularExpression) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.begin { [weak self] result in
            guard result == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: pdfURL, to: dest)
                DispatchQueue.main.async {
                    self?.setStatus("已保存到 \(dest.path)", .ok)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setStatus("保存失败：\(error.localizedDescription)", .err)
                }
            }
        }
    }

    // MARK: - Helpers

    private func setStatus(_ msg: String, _ kind: StatusKind) {
        statusMessage = msg
        statusKind = kind
    }

    /// 各页物理尺寸（去重后）。用于告警「页面尺寸不一致」。
    ///
    /// 【为何改用 PDFKit】原先调 poppler 的 `pdfinfo` 解析文本输出。而 poppler
    /// 是本项目唯一需要成串动态库（libpoppler / liblcms2 / freetype / fontconfig…）
    /// 的依赖，为把 app 做成自包含可分发，它那棵依赖树的重定位成本远高于收益 ——
    /// 而它在此处只做一件事：读页面尺寸，PDFKit 原生就能做，且免去解析文本、
    /// 免去正则（此前正则漏取捕获组，导致每页都被判为不同尺寸而恒亮告警）。
    ///
    /// mediaBox 与 pdfinfo 的 "Page N size" 同源，故数值与旧实现一致。
    private func getPageSizes(pdf: URL, pages: Int) -> [String] {
        guard let doc = PDFDocument(url: pdf) else { return [] }
        var sizes = Set<String>()
        for i in 0..<min(pages, doc.pageCount) {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            // 保留三位小数并与旧格式一致（"445.323 x 593.858"），
            // 使既有的一致性比较与界面展示无需改动。
            sizes.insert(String(format: "%.3f x %.3f", b.width, b.height))
        }
        return sizes.sorted()
    }

    @discardableResult
    /// 把裸命令名解析为绝对路径；已是绝对路径则原样返回。
    private static func resolveExecutable(_ cmd: String) -> String {
        guard !cmd.hasPrefix("/") else { return cmd }
        // bundle 内自带的引擎优先 —— 目标机可能根本没有 Homebrew。
        var searchPaths: [String] = []
        if let res = Bundle.main.resourceURL {
            searchPaths.append(res.appendingPathComponent("bin").path)
        }
        searchPaths += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for dir in searchPaths {
            let candidate = dir + "/" + cmd
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return cmd   // 交给 Process 报错，调用方已有失败分支
    }

    private func runShell(_ args: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let proc = Process()
        // executableURL 不做 PATH 查找 —— 设 environment["PATH"] 只影响孙进程。
        // 故裸命令名（"typst"/"pdftoppm"）必须自行解析成绝对路径，
        // 否则从 Finder 启动时必然启动失败（Homebrew 不在 launchd 的默认 PATH 里）。
        proc.executableURL = URL(fileURLWithPath: Self.resolveExecutable(args[0]))
        proc.arguments = Array(args.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["TRUESCALE_WORKDIR"] = FileManager.default.temporaryDirectory.path
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do { try proc.run() } catch {
            return ("", error.localizedDescription, -1)
        }
        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            proc.terminationStatus
        )
    }

    private func shellCommandExists(_ cmd: String) -> Bool {
        let r = runShell(["/bin/sh", "-c", "command -v \(cmd)"])
        return r.exitCode == 0
    }

    static func parseErrorMessage(_ rawStderr: String) -> String {
        let lines = rawStderr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 优先提取 Typst/Pandoc 明确抛出的 error: 报错行
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("error:") || lower.hasPrefix("error :") {
                return line
            }
        }

        // 寻找具体的 ❌ 错误点（排除“渲染未完成”）
        for line in lines {
            if line.contains("❌") && !line.contains("渲染未完成") {
                return line.replacingOccurrences(of: "❌ ", with: "")
            }
        }

        // 提取倒数关键有效信息，跳过纯提示和 ASCII 诊断代码块
        for line in lines.reversed() {
            if line.contains("渲染未完成") || line.contains("Error producing PDF.") {
                continue
            }
            if !line.hasPrefix("┌─") && !line.hasPrefix("│") && !line.hasPrefix("└─") {
                return String(line.suffix(150))
            }
        }

        return lines.first(where: { $0.contains("❌") })?.replacingOccurrences(of: "❌ ", with: "") ?? "渲染未完成"
    }
}
