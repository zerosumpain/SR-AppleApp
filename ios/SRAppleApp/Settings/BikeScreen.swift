import CoreBluetooth
import SwiftUI

/// Settings → Bike: tell this phone which Bluetooth device is the e-bike, so
/// the fixes taken while it is connected are marked and /health can call the
/// journey a ride. See `BikePresence` for what is and is not read.
struct BikeScreen: View {
    @ObservedObject var bike: BikePresence
    /// A service UUID typed by hand, for a bike that offers neither of the
    /// standard services. The field test in docs/BIKE.md says what to type.
    @State private var extra = ""
    @State private var checked: Bool?

    var body: some View {
        List {
            if let chosen = bike.bike {
                Section {
                    SRRow(title: chosen.name, subtitle: status, icon: "bicycle") {
                        if checked == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.good)
                        }
                    }
                    .srGlassRow()
                    Button("Check now") { check() }
                        .srGlassRow()
                        .accessibilityIdentifier("bike-check")
                    Button("Forget this bike", role: .destructive) {
                        bike.forget()
                        checked = nil
                    }
                    .srGlassRow()
                } header: {
                    SRSectionLabel(text: "Your bike")
                } footer: {
                    Text("Fixes taken while it is connected are marked as on the bike. The Avinox app must be connected to it during the ride for that to happen.")
                        .font(SR.Text.secondary())
                }
                .onAppear { check() }
            } else {
                Section {
                    Text("Turn the bike on and open the Avinox app so the bike is connected, then search.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                    TextField("Bike's own service UUID (optional)", text: $extra)
                        .font(SR.Text.mono(13))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .srGlassRow()
                    Button(bike.searched ? "Search again" : "Search for connected devices") {
                        bike.search(extra: extra)
                    }
                    .srGlassRow()
                    .accessibilityIdentifier("bike-search")
                } header: {
                    SRSectionLabel(text: "Find your bike")
                } footer: {
                    if let refusal { Text(refusal).font(SR.Text.secondary()) }
                }

                if bike.searched {
                    Section {
                        if bike.candidates.isEmpty {
                            Text("Nothing connected offers a service this can look for. Add the bike's own service from the nRF Connect test and search again.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(bike.candidates) { candidate in
                            Button {
                                bike.choose(candidate, extra: extra)
                            } label: {
                                SRRow(title: candidate.name, subtitle: String(candidate.id.uuidString.prefix(8)), icon: "dot.radiowaves.left.and.right")
                            }
                            .srGlassRow()
                        }
                    } header: {
                        SRSectionLabel(text: "Connected now")
                    }
                }
            }

            Section {
                Text("This app never connects to the bike, reads its data or changes its settings. It only asks iOS whether the bike is connected, and only while it is already recording your location.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } header: {
                SRSectionLabel(text: "What it reads")
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        // The manager reports its state a moment after it is made, so the
        // first check on opening usually lands before it can answer.
        .onChange(of: bike.state) { check() }
        .navigationTitle("Bike")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var status: String {
        switch checked {
        case .some(true): return "Connected now"
        case .some(false): return "Not connected"
        case .none: return refusal ?? "Not checked yet"
        }
    }

    /// Why nothing can be seen, when the reason is Bluetooth itself.
    private var refusal: String? {
        switch bike.authorization {
        case .denied: return "Bluetooth is off for SR Companion. Turn it on in the iOS Settings app."
        case .restricted: return "Bluetooth is restricted on this phone."
        default: break
        }
        return bike.state == .poweredOff ? "Bluetooth is switched off." : nil
    }

    private func check() {
        bike.resume()
        checked = bike.state == .poweredOn ? (bike.connectedNow(fresh: true) == true) : nil
    }
}
