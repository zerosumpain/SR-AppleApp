import SwiftUI

private enum SiteDestination: String, CaseIterable, Identifiable {
    case jkai, news, health
    var id: String { rawValue }
    var title: String {
        switch self { case .jkai: return "JKAI"; case .news: return "News"; case .health: return "Health" }
    }
    var detail: String {
        switch self {
        case .jkai: return "Conversations and tools"
        case .news: return "Your news reading desk"
        case .health: return "Your website health dashboard"
        }
    }
    var icon: String {
        switch self {
        case .jkai: return "bubble.left.and.bubble.right"
        case .news: return "newspaper"
        case .health: return "heart.text.square"
        }
    }
    var url: URL { URL(string: "https://strangeramblings.com/\(rawValue)")! }
}

struct SiteLinksView: View {
    @State private var destination = SiteDestination.jkai
    @State private var browserPresented = false
    @State private var loadFailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore Strange Ramblings").font(.headline)
            ForEach(SiteDestination.allCases) { item in
                Button {
                    destination = item; loadFailed = false; browserPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.title3).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("site-\(item.rawValue)")
                .accessibilityLabel("Open \(item.title)")
            }
            if loadFailed {
                Text("\(destination.title) could not load. Check your connection and try again.").font(.callout)
                Link("Try in Safari", destination: destination.url)
            }
        }
        .background {
            SiteBrowserPresenter(url: destination.url, isPresented: $browserPresented) { loadFailed = true }
                .frame(width: 0, height: 0)
        }
    }
}
