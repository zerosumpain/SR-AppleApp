import SwiftUI

/// A person's circle: their initials on their own colour — the colour their
/// pin, Orbit body and ribbon wear (`SR.PersonHue`), so a line in msg family
/// and a dot on the map are plainly the same person.
///
/// The colours are dealt over the household's subjects, so they come from the
/// family view this phone was last sent (`FamilyStore.current`). Somebody the
/// view does not hold — an older site that sent no subject, or a person not
/// on the household — still gets a steady colour, from their id.
struct FamilyFaces {
    private let colours: [String: Color]
    private let initials: [String: String]

    /// From the family view this phone was last sent.
    @MainActor
    init() {
        self.init(view: FamilyStore.current?.view)
    }

    @MainActor
    init(view: HouseholdView?) {
        let people = view?.people ?? []
        colours = SR.PersonHue.assign(people.map(\.subject))
        initials = view?.initials ?? [:]
    }

    func colour(subject: String?, id: String) -> Color {
        if let subject, let colour = colours[subject] { return colour }
        let palette = SR.PersonHue.all
        guard !palette.isEmpty else { return SR.accent }
        // A stable spot from the id's characters: no hashing seed varies by launch.
        let spot = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return palette[spot % palette.count]
    }

    func initials(subject: String?, name: String) -> String {
        if let subject, let known = initials[subject] { return known }
        return HouseholdView.twoLetters(name)
    }
}

struct FamilyFace: View {
    let subject: String?
    let id: String
    let name: String
    var size: CGFloat = 32
    let faces: FamilyFaces

    var body: some View {
        Text(faces.initials(subject: subject, name: name))
            .font(SR.monoBold(size * 0.4))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: size, height: size)
            .background(faces.colour(subject: subject, id: id), in: Circle())
            .overlay(Circle().stroke(SR.paper, lineWidth: size > 30 ? 2 : 1.5))
            .accessibilityHidden(true)
    }
}
