import Foundation

/// The desk when a thread has nothing on it yet: Today, as a page.
///
/// The site's desk opens on a Today page for an empty thread — the briefing
/// moved off the chat column and onto the desk. The phone already has every
/// figure for it in `/api/native/today` (the Today tab's one request), so this
/// builds the same page from that payload and the drawer draws it with the same
/// blocks as any other. PURE: payload in, page out, so it is tested.
enum DeskToday {
    static func page(from payload: TodayPayload?, now: Date = Date(), calendar: Calendar = .current) -> PanelPage {
        var sections: [PanelSection] = []

        if let health = payload?.health {
            var figures: [PanelFigure] = []
            if let readiness = health.readiness {
                figures.append(PanelFigure(
                    label: "Readiness",
                    value: String(Int(readiness.score.rounded())),
                    delta: readiness.label
                ))
            }
            for figure in health.figures.prefix(5) {
                figures.append(PanelFigure(
                    label: figure.label,
                    value: figure.measured ? figure.display : "—",
                    unit: figure.measured ? unit(of: figure) : nil,
                    delta: figure.deltaDisplay,
                    direction: figure.direction,
                    spark: figure.series ?? []
                ))
            }
            var blocks: [PanelBlock] = []
            if !figures.isEmpty {
                blocks.append(PanelBlock(id: "today-figures", source: health.isMock ? "demonstration figures" : nil, content: .figures(figures)))
            }
            if let readiness = health.readiness, !readiness.factors.isEmpty {
                let lowest = readiness.factors.min { $0.score < $1.score }?.key
                blocks.append(PanelBlock(
                    id: "today-readiness",
                    title: "Readiness, by part",
                    note: "\(Int(readiness.score.rounded())) · \(readiness.label)",
                    foot: readiness.recommendation.isEmpty ? nil : readiness.recommendation,
                    source: "from /health",
                    href: "/health",
                    content: .bars(readiness.factors.map {
                        PanelBar(id: $0.key, label: $0.label, value: $0.score,
                                 display: String(Int($0.score.rounded())), highlight: $0.key == lowest)
                    })
                ))
            }
            if !blocks.isEmpty {
                sections.append(PanelSection(id: "today-health", label: "Body", blocks: blocks))
            }
        }

        if let alerts = payload?.alerts {
            let rows = alerts.latest.prefix(3).map { alert in
                PanelRow(
                    id: alert.id,
                    title: alert.title,
                    sub: alert.category.capitalized,
                    meta: shortAgo(alert.createdAt),
                    tone: ["alert", "high", "warn"].contains(alert.severity) ? "warn" : nil
                )
            }
            sections.append(PanelSection(id: "today-alerts", label: "Alerts", blocks: [
                PanelBlock(
                    id: "today-alerts-rows",
                    note: alerts.unread == 1 ? "1 unread" : "\(alerts.unread) unread",
                    content: .rows(Array(rows), numbered: false, empty: "Nothing waiting on you.")
                ),
            ]))
        }

        if let news = payload?.news, !news.stories.isEmpty {
            let rows = news.stories.prefix(3).map { story in
                PanelRow(id: story.key, title: story.title, meta: story.sourceLabel, href: story.url, external: true)
            }
            sections.append(PanelSection(id: "today-news", label: "Headlines", blocks: [
                PanelBlock(id: "today-news-rows", content: .rows(Array(rows), numbered: true, empty: nil)),
            ]))
        }

        if sections.isEmpty {
            sections.append(PanelSection(id: "today-empty", blocks: [
                PanelBlock(id: "today-empty-prose", content: .prose(
                    "Nothing on the desk yet. Ask something and the evidence for the answer lands here: the figures, the sources, the rows it read.",
                    tone: nil
                )),
            ]))
        }

        return PanelPage(
            producer: "today",
            head: PanelHead(
                kicker: "Today",
                context: [dayLine(now, calendar: calendar)],
                title: greeting(now, calendar: calendar),
                standfirst: payload?.health?.readiness?.recommendation.nilIfEmpty
                    ?? "What the site knows this morning, until this thread puts something on the desk."
            ),
            sections: sections
        )
    }

    /// The unit to print beside a figure. Hours are already in the display
    /// string ("7h 24m"); percent is not ("68"), see `displayWithUnit`.
    static func unit(of figure: HealthFigure) -> String? {
        switch figure.unit {
        case "h", "": return nil
        default: return figure.unit
        }
    }

    static func greeting(_ now: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static func dayLine(_ now: Date, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_GB")
        format.dateFormat = "EEE d MMM"
        return format.string(from: now)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
