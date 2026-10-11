import SwiftUI

struct NotificationsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @State private var items: [AppNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !services.isSignedIn {
                Text("notifications.signIn").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button {
                    if let url = item.url { openURL(url) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(item.isRead ? Color.clear : Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).bold()
                            if !item.body.isEmpty {
                                Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(BGDate.string(item.createdAt, date: .medium, time: .short))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .overlay {
            if services.isSignedIn && !isLoading && items.isEmpty {
                ContentUnavailableView("notifications.empty", systemImage: "bell.slash")
            }
        }
        .navigationTitle("notifications.title")
        .toolbar {
            if services.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("notifications.settings"))
                }
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        guard services.isSignedIn else { return }
        do {
            items = try await services.notifications.notifications()
            errorMessage = nil
            if items.contains(where: { !$0.isRead }) {
                try? await services.notifications.markAllRead()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var prefs = NotificationPreferences()
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button("notifications.enablePush") {
                    Task { await PushManager.shared.requestAuthorization() }
                }
            } footer: {
                Text("notifications.enablePush.footer")
            }
            Section {
                Toggle("notifications.pref.events", isOn: $prefs.newEvents)
                Toggle("notifications.pref.openMats", isOn: $prefs.openMatsFollowed)
            } header: {
Text("notifications.prefs")
} footer: {
                Text("notifications.pref.footer")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("notifications.settings")
        .task {
            prefs = (try? await services.notifications.preferences()) ?? NotificationPreferences()
            loaded = true
        }
        .onChange(of: prefs) { _, newValue in
            guard loaded else { return }
            Task {
                do {
                    try await services.notifications.savePreferences(newValue)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
