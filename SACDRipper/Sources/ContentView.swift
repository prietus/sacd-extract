import SwiftUI

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case rip, fixISO
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rip: return "Rip"
        case .fixISO: return "Fix ISO"
        }
    }
    var icon: String {
        switch self {
        case .rip: return "opticaldisc"
        case .fixISO: return "bandage"
        }
    }
    var subtitle: String {
        switch self {
        case .rip: return "SACD → DSF / DSDIFF / ISO"
        case .fixISO: return "Strip 2064-byte sectors"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppSection = .rip
    @StateObject private var ripController = RipController()
    @StateObject private var fixController = FixISOController()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title).font(.body.weight(.medium))
                                    Text(section.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: section.icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                } header: {
                    Text("SACD Ripper").font(.headline)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            Group {
                switch selection {
                case .rip: RipView(controller: ripController)
                case .fixISO: FixISOView(controller: fixController)
                }
            }
            .navigationTitle(selection.title)
        }
    }
}
