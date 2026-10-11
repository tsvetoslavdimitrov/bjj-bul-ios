import SwiftUI

/// Gyms and coaches share one tab so the tab bar stays at five items.
struct DirectoryView: View {
    enum Mode: String, CaseIterable, Hashable {
        case gyms, coaches
    }

    @State private var mode: Mode = .gyms

    var body: some View {
        Group {
            switch mode {
            case .gyms:
                GymListView()
            case .coaches:
                CoachListView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("directory.mode", selection: $mode) {
                Text("tab.gyms").tag(Mode.gyms)
                Text("tab.coaches").tag(Mode.coaches)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
