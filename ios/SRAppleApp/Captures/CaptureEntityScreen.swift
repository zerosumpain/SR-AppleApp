import SwiftUI

/// Somebody or something from the owner's captures: what the graph says of
/// them, every capture that mentions them, and what they are linked to.
struct CaptureEntityScreen: View {
    let ref: CaptureEntityRef

    @ObservedObject private var store = CaptureStore.shared
    @State private var page: CaptureEntityPage?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                SRPageHeader(
                    kicker: page?.entity.type ?? "",
                    title: page?.entity.name ?? ref.name,
                    strap: page?.entity.summary
                )
                .srBareRow()
            }
            if let error {
                Section {
                    SREmpty(title: "This didn't load", icon: "wifi.exclamationmark", message: error,
                            actionLabel: "Try again", action: { Task { await load() } })
                        .listRowBackground(Color.clear)
                }
            } else if let page {
                Section {
                    if page.captures.isEmpty {
                        Text("No capture mentions them any more.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .srGlassRow()
                    }
                    ForEach(page.captures) { item in
                        NavigationLink(value: CaptureRef(id: item.id)) {
                            CaptureSummaryRow(item: item)
                        }
                        .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "In your captures", trailing: "\(page.captures.count)")
                }
                if !page.neighbours.isEmpty {
                    Section {
                        ForEach(page.neighbours) { neighbour in
                            NavigationLink(value: CaptureEntityRef(id: neighbour.id, name: neighbour.name)) {
                                SRRow(title: neighbour.name, subtitle: neighbour.relation.isEmpty ? nil : neighbour.relation,
                                      icon: CaptureEntityKind.symbol(neighbour.type))
                            }
                            .srGlassRow()
                        }
                    } header: {
                        SRSectionLabel(text: "Linked to")
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .srRefreshable { await load() }
        .accessibilityIdentifier("capture-entity")
    }

    private func load() async {
        do {
            page = try await store.entity(ref.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
