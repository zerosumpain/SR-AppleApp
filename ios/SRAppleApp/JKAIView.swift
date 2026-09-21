import SwiftUI

struct JKAIView: View {
    @State private var browserPresented = false
    @State private var loadError: String?
    private let chatURL = URL(string: "https://strangeramblings.com/jkai")!
    private let paper = Color(red: 0.929, green: 0.894, blue: 0.831)
    private let ink = Color(red: 0.102, green: 0.063, blue: 0.031)
    private let accent = Color(red: 0.769, green: 0.341, blue: 0.039)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("STRANGE RAMBLINGS / JKAI").font(.system(.caption, design: .monospaced)).tracking(1)
                    Text("A place to think.").font(.system(size: 44, weight: .black)).tracking(-2).accessibilityAddTraits(.isHeader)
                    Text("Pick up a conversation, explore an idea, or start something new.").font(.title3)
                    Divider()
                    Label("Your existing JKAI workspace", systemImage: "bubble.left.and.bubble.right").font(.headline)
                    Text("Open your conversations and tools with the same mobile chat you use on the website.")
                    Button {
                        loadError = nil
                        browserPresented = true
                    } label: {
                        Label("Open JKAI chat", systemImage: "bubble.left.and.text.bubble.right")
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("open-jkai-chat")
                    Text("Sign in with your Strange Ramblings Google account. Your existing JKAI access permissions apply.").font(.callout)
                    Text("Tap Close in the chat browser to return to your health and family views.").font(.callout).foregroundStyle(.secondary)
                    if let loadError {
                        Text(loadError).font(.callout).accessibilityIdentifier("jkai-load-error")
                        Link("Try in Safari", destination: chatURL)
                    }
                }.padding(22)
            }
            .background(paper.ignoresSafeArea(.container)).foregroundStyle(ink).tint(accent)
            .navigationTitle("JKAI").navigationBarTitleDisplayMode(.inline)
            .background {
                SiteBrowserPresenter(url: chatURL, isPresented: $browserPresented) {
                    loadError = "JKAI could not load. Check your connection and try again."
                }.frame(width: 0, height: 0)
            }
        }.preferredColorScheme(.light)
    }
}

