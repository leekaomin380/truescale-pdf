import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = ConversionViewModel()
    @State private var isDragOver = false
    @State private var previewImage: NSImage?
    @State private var showFilePicker = false
    @AppStorage("isAdvancedExpanded") private var isAdvancedExpanded = false

    private let cjkNames: [String: String] = [
        "PingFang SC": "苹方", "Songti SC": "宋体", "Heiti SC": "黑体",
        "STSong": "华文宋体", "Hiragino Sans GB": "冬青黑体",
        "Noto Serif CJK SC": "思源宋体", "Source Han Sans SC": "思源黑体",
        "Source Han Serif SC": "思源宋体"
    ]

    private func cjkDisplayName(for name: String) -> String {
        if let cn = cjkNames[name] {
            return "\(cn) (\(name))"
        }
        return name
    }

    /// 是否已有可渲染的 EPUB 输入。
    /// 另存不再要求「必须先预览」—— 它会在内容脱节时自行重渲（见 vm.ensureFresh），
    /// 故按钮条件与「预览」一致：有输入即可点。
    private var hasInput: Bool {
        vm.sourceFileURL != nil
    }

    /// 页框尺寸：按目标页面的真实宽高比，等比放进可用空间。
    /// 有无预览都用同一个框 —— 未转换时用户也能看到内容将落在多大的版面里。
    private func pageBox(in available: CGSize) -> CGSize {
        let wmm = Double(vm.config.pageW.replacingOccurrences(of: "mm", with: "")) ?? 210.0
        let hmm = Double(vm.config.pageH.replacingOccurrences(of: "mm", with: "")) ?? 297.0
        guard wmm > 0, hmm > 0 else { return available }
        let maxW = max(available.width - 48, 40)
        let maxH = max(available.height - 32, 40)
        let scale = min(maxW / wmm, maxH / hmm)
        return CGSize(width: wmm * scale, height: hmm * scale)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, idealWidth: 310, maxWidth: 340)
            previewArea
        }
        .onChange(of: vm.currentPage) { _, _ in
            updatePreview()
        }
        // 排版参数一改就落盘。
        // 【为何逐项监听而不在退出时统一保存】app 是常驻型（关窗不退出），
        // 「退出时保存」在异常退出或强制关闭时会丢；而这些值改动频率极低，
        // 每次写一个 UserDefaults 字典的开销可以忽略。
        .onChange(of: vm.selectedPresetID)   { _, _ in vm.savePreferences() }
        .onChange(of: vm.selectedCjkFont)     { _, _ in vm.savePreferences() }
        .onChange(of: vm.selectedLatinFont)   { _, _ in vm.savePreferences() }
        .onChange(of: vm.bodySize)            { _, _ in vm.savePreferences() }
        .onChange(of: vm.margin)              { _, _ in vm.savePreferences() }
        .onChange(of: vm.leading)             { _, _ in vm.savePreferences() }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("文件转 PDF")
                    .font(.headline)

                epubSection

                Divider()

                layoutBasicSection

                DisclosureGroup("进阶设置", isExpanded: $isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        fontSection
                        layoutAdvancedSection
                    }
                    .padding(.top, 4)
                }

                Divider()

                actionButtons
                statusBar
            }
            .padding(16)
        }
    }

    private var epubSection: some View {
        Group {
            Button(action: { showFilePicker = true }) {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(isDragOver ? .accentColor : .secondary)
                    Text(isDragOver ? "松开载入" : "拖入文件或点击选择")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("EPUB / HTML / FB2 / Markdown")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: SupportedFileFormat.allowedExtensions.compactMap { UTType(filenameExtension: $0) },
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = vm.selectSourceFile(url: url)
                }
            }

            if !vm.sourceFileName.isEmpty {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text(vm.sourceFileName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let typeName = vm.sourceFileTypeDisplayName {
                        Text(typeName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        vm.clearSourceFile()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    private var fontSection: some View {
        Group {
            Text("中文字体")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $vm.selectedCjkFont) {
                ForEach(vm.cjkFonts, id: \.self) { f in
                    Text(cjkDisplayName(for: f)).tag(f)
                }
            }
            .pickerStyle(.menu)

            Text("西文字体")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $vm.selectedLatinFont) {
                ForEach(vm.latinFonts, id: \.self) { f in
                    Text(f).tag(f)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var layoutBasicSection: some View {
        Group {
            Text("页面尺寸")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $vm.selectedPresetID) {
                ForEach(ConversionViewModel.pagePresets) { preset in
                    Text(preset.displayName).tag(preset.id)
                }
            }
            .pickerStyle(.menu)

            if let explanation = vm.selectedPreset.secondaryExplanation {
                Text(explanation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text("正文字号")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $vm.bodySize) {
                ForEach(ConversionViewModel.bodySizeChoices, id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .pickerStyle(.menu)

            if let m = vm.renderMetrics {
                HStack(spacing: 4) {
                    Text("中文 \(m.cjkPerLine) 字/行")
                        .font(.caption2)
                        .foregroundColor(m.cjkPerLine >= 28 && m.cjkPerLine <= 40 ? .green : .orange)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("西文 \(m.latinPerLine) 字符/行")
                        .font(.caption2)
                        .foregroundColor(m.latinPerLine >= 45 && m.latinPerLine <= 75 ? .green : .orange)
                }
            }

            Text("行距")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $vm.leading) {
                ForEach(ConversionViewModel.leadingChoices, id: \.0) { pair in
                    Text(pair.1).tag(pair.0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var layoutAdvancedSection: some View {
        Group {
            HStack {
                VStack(alignment: .leading) {
                    Text("页边距")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $vm.margin) {
                        ForEach(ConversionViewModel.marginChoices, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading) {
                    Text("页脚时间")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("开启", isOn: $vm.printTime)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    private var actionButtons: some View {
        Group {
            Button(action: { vm.convertEpub() }) {
                HStack {
                    if vm.isConverting {
                        ProgressView().controlSize(.small)
                    }
                    Text("预览")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isConverting || vm.sourceFileURL == nil)
            .keyboardShortcut(.return, modifiers: .command)

            Button(action: { vm.ensureFresh { vm.savePDF() } }) {
                Text("另存 PDF…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isConverting || !hasInput)
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var statusBar: some View {
        Group {
            if !vm.statusMessage.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusColor.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }

    private var statusColor: Color {
        switch vm.statusKind {
        case .ok: return .green
        case .err: return .red
        case .run: return .orange
        case .info: return .secondary
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        VStack(spacing: 0) {
            // Page bar
            HStack(spacing: 8) {
                Button(action: { vm.currentPage = max(1, vm.currentPage - 1) }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(vm.currentPage <= 1)

                Text("第")
                TextField("", value: $vm.currentPage, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .onSubmit { vm.currentPage = max(1, min(vm.totalPages, vm.currentPage)) }
                Text("/ \(vm.totalPages) 页")
                    .foregroundColor(.secondary)

                Button(action: { vm.currentPage = min(vm.totalPages, vm.currentPage + 1) }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(vm.currentPage >= vm.totalPages)

                Spacer()

                if let m = vm.renderMetrics {
                    if m.sizeUniform {
                        Label("页面尺寸统一", systemImage: "checkmark.seal")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label("尺寸不一致", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Preview —— 页框始终按目标页面的真实宽高比呈现，
            // 未转换时同样显示该幅面，让用户先看到「内容会落在多大的版面里」。
            GeometryReader { geo in
                let box = pageBox(in: geo.size)
                ZStack {
                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: box.width, height: box.height)
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .textBackgroundColor))
                            .frame(width: box.width, height: box.height)
                            .overlay(
                                Text("准备就绪")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: box.width, height: box.height)
                .overlay(
                    Rectangle()
                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(Color(nsColor: .controlBackgroundColor))

            // Bottom info bar
            HStack(spacing: 16) {
                Text("页面 \(vm.selectedPreset.name) (\(vm.config.pageW) × \(vm.config.pageH))")
                    .font(.caption2).foregroundColor(.secondary)
                if let m = vm.renderMetrics {
                    Text("版心 \(String(format: "%.1f", m.measureMm))mm")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("字号 \(vm.bodySize)")
                        .font(.caption2).foregroundColor(.secondary)
                    if m.pages > 0 {
                        Text("共 \(m.pages) 页")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        // 观察世代号而非 currentPdfURL —— 后者在只改排版参数时不会变化
        // （输出路径是确定性的），会导致预览停留在上一次渲染。
        .onChange(of: vm.renderGeneration) { _, _ in updatePreview() }
    }

    // MARK: - Actions

    private func updatePreview() {
        guard let img = vm.renderPage(vm.currentPage) else {
            previewImage = nil
            return
        }
        previewImage = img
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "epub" else { return }
            DispatchQueue.main.async {
                _ = vm.selectSourceFile(url: url)
            }
        }
        return true
    }
}
