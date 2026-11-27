import AppKit
import SwiftUI
import WebKit

struct ImagePreviewView: View {
    let url: URL
    @ObservedObject var state: AppState

    private var isSVG: Bool {
        url.pathExtension.lowercased() == "svg"
    }

    private var nsImage: NSImage? {
        guard !isSVG else { return nil }
        return NSImage(contentsOf: url)
    }

    private var pixelSizeText: String {
        if isSVG { return "矢量 SVG" }
        guard let img = nsImage else { return "未知尺寸" }
        if let rep = img.representations.first, rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh) px"
        }
        return "\(Int(img.size.width)) × \(Int(img.size.height)) pt"
    }

    private var fileSizeText: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact image toolbar
            HStack(spacing: 12) {
                Text(pixelSizeText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.62))

                if !fileSizeText.isEmpty {
                    Text("· \(fileSizeText)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.50))
                }

                Spacer()

                Button {
                    state.imageFitToWindow = true
                    state.imageZoom = 1.0
                } label: {
                    Text("适应窗口")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(state.imageFitToWindow ? Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.24) : Color.white.opacity(0.06))
                        )
                        .foregroundStyle(state.imageFitToWindow ? Color(red: 0.68, green: 0.80, blue: 1.0) : Color(white: 0.78))
                }
                .buttonStyle(.plain)

                Button {
                    state.imageFitToWindow = false
                    state.imageZoom = 1.0
                } label: {
                    Text("100%")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(!state.imageFitToWindow && abs(state.imageZoom - 1.0) < 0.01 ? Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.24) : Color.white.opacity(0.06))
                        )
                        .foregroundStyle(Color(white: 0.80))
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Button {
                        state.imageFitToWindow = false
                        state.imageZoom = max(0.2, state.imageZoom - 0.2)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(white: 0.70))
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { state.imageZoom },
                            set: {
                                state.imageFitToWindow = false
                                state.imageZoom = $0
                            }
                        ),
                        in: 0.2...4.0
                    )
                    .frame(width: 96)
                    .tint(Color(red: 0.478, green: 0.635, blue: 0.969))

                    Button {
                        state.imageFitToWindow = false
                        state.imageZoom = min(4.0, state.imageZoom + 0.2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(white: 0.70))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(state.imageZoom * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.62))
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.098, green: 0.100, blue: 0.112))

            Rectangle()
                .fill(Color(white: 0.15))
                .frame(height: 1)

            // Image canvas
            GeometryReader { geo in
                ZStack {
                    Color(red: 0.086, green: 0.088, blue: 0.098)

                    if isSVG {
                        SVGImageWebView(url: url, zoom: state.imageFitToWindow ? 1.0 : state.imageZoom)
                    } else if let img = nsImage {
                        if state.imageFitToWindow {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: max(geo.size.width - 48, 100), maxHeight: max(geo.size.height - 48, 100))
                                .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(
                                        width: img.size.width * state.imageZoom,
                                        height: img.size.height * state.imageZoom
                                    )
                                    .padding(32)
                                    .frame(
                                        minWidth: geo.size.width,
                                        minHeight: geo.size.height
                                    )
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Color(white: 0.45))
                            Text("无法加载图片：\(url.lastPathComponent)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(white: 0.58))
                        }
                    }
                }
            }
        }
    }
}

private struct SVGImageWebView: NSViewRepresentable {
    let url: URL
    let zoom: Double

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        loadSVG(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadSVG(into: webView)
    }

    private func loadSVG(into webView: WKWebView) {
        let svgContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"><style>
          html, body {
            margin: 0; padding: 24px; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
            background: #16161A; box-sizing: border-box;
          }
          .wrap { transform: scale(\(zoom)); transform-origin: center center; }
          svg { max-width: 90vw; max-height: 85vh; height: auto; }
        </style></head>
        <body><div class="wrap">\(svgContent)</div></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
