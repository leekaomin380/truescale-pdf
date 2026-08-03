import AppKit
import SwiftUI

struct OpenSourceComponent: Identifiable {
    let name: String
    let version: String
    let license: String
    let purpose: String

    var id: String { name }
}

struct OpenSourceComponentsView: View {
    @Environment(\.dismiss) private var dismiss

    private let components = [
        OpenSourceComponent(
            name: "Pandoc", version: "3.10", license: "GPL-2.0-or-later",
            purpose: "解析 EPUB 电子书"
        ),
        OpenSourceComponent(
            name: "GNU MP", version: "6.3.0", license: "GPLv2 分发路径",
            purpose: "Pandoc 使用的高精度算术动态库"
        ),
        OpenSourceComponent(
            name: "Typst", version: "0.15.1", license: "Apache-2.0",
            purpose: "生成固定尺寸 PDF"
        )
    ]

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var releaseURL: URL? {
        URL(string: "https://github.com/leekaomin380/truescale-pdf/releases/tag/v\(appVersion)")
    }

    private var licensesURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("licenses", isDirectory: true)
    }

    private var correspondingSourceURL: URL? {
        licensesURL?.appendingPathComponent("corresponding-source", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开源组件")
                        .font(.title2.bold())
                    Text("Epub 转 PDF \(appVersion)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("本应用包含以下独立开源组件。各组件保留原有版权与许可；许可证全文、与本版本二进制对应的源码及构建修改材料均随应用提供。")
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("组件").fontWeight(.semibold)
                    Text("版本").fontWeight(.semibold)
                    Text("许可").fontWeight(.semibold)
                    Text("用途").fontWeight(.semibold)
                }
                Divider().gridCellColumns(4)
                ForEach(components) { component in
                    GridRow {
                        Text(component.name)
                        Text(component.version)
                        Text(component.license)
                        Text(component.purpose)
                    }
                }
            }
            .font(.callout)

            Text("Epub 转 PDF 与上述项目不存在官方隶属、赞助或背书关系。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("查看随包源码") {
                    reveal(correspondingSourceURL)
                }
                .disabled(correspondingSourceURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)

                Button("查看许可证") {
                    reveal(licensesURL)
                }
                .disabled(licensesURL == nil)

                if let releaseURL {
                    Link("GitHub Release", destination: releaseURL)
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 720)
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
