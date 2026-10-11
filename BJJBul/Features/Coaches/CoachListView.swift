import SwiftUI

/// Coach directory list (embedded in Explore's NavigationStack).
struct CoachListContent: View {
    @Environment(AppServices.self) private var services
    @State private var coaches: [Coach] = []
    @State private var searchText = ""
    @State private var beltFilter: Belt?
    @State private var isLoading = true

    private var filtered: [Coach] {
        coaches.filter { coach in
            let matchesBelt = beltFilter == nil || coach.belt == beltFilter
            let matchesSearch = searchText.isEmpty
                || coach.fullName.localizedCaseInsensitiveContains(searchText)
                || (coach.fullNameLatin ?? "").localizedCaseInsensitiveContains(searchText)
            return matchesBelt && matchesSearch
        }
    }

    var body: some View {
            List(filtered) { coach in
                NavigationLink(value: coach) {
                    CoachRowView(coach: coach)
                }
            }
            .overlay {
                if !isLoading && filtered.isEmpty {
                    ContentUnavailableView("coaches.empty", systemImage: "person.2.slash")
                }
            }
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("coaches.filter.belt", selection: $beltFilter) {
                            Text("coaches.filter.all").tag(Belt?.none)
                            ForEach(Belt.allCases, id: \.self) { belt in
                                Text(LocalizedStringKey(belt.localizedKey)).tag(Belt?.some(belt))
                            }
                        }
                    } label: {
                        Image(systemName: beltFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .task {
                coaches = (try? await services.coaches.coaches()) ?? []
                isLoading = false
            }
    }
}

struct CoachRowView: View {
    let coach: Coach

    var body: some View {
        HStack(spacing: 12) {
            CoachPhotoView(url: coach.photoURL, size: 44)
            VStack(alignment: .leading) {
                Text(coach.fullName).font(.headline)
                Text(LocalizedStringKey(coach.belt.localizedKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CoachPhotoView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
