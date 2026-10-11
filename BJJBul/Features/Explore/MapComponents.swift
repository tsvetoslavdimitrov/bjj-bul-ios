import SwiftUI
import MapKit

extension Gym {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension City {
    var localizedName: String {
        Locale.current.language.languageCode?.identifier == "bg" ? nameBg : nameEn
    }
}

/// A small BJJ-belt bar: black belt with red tip for verified gyms, white belt with black tip otherwise.
struct BeltAccent: View {
    let verified: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(verified ? Color.black : Color.white)
            Rectangle().fill(verified ? Color.red : Color.black).frame(width: 5)
        }
        .frame(width: 20, height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
    }
}

struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Map chip: belt accent + gym name (name hidden when zoomed out unless selected).
struct GymPinView: View {
    let gym: Gym
    let isSelected: Bool
    let showsLabel: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                BeltAccent(verified: gym.verified)
                if showsLabel || isSelected {
                    Text(gym.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: 160)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color(uiColor: .systemBackground))
            )
            .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 3, y: 1)
            PinTail()
                .fill(isSelected ? Color.accentColor : Color(uiColor: .systemBackground))
                .frame(width: 10, height: 6)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct ClusterBubble: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.subheadline)
            .bold()
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1)
    }
}

struct GymCluster: Identifiable {
    let id: String
    let gyms: [Gym]
    let coordinate: CLLocationCoordinate2D
}

/// Simple grid clustering based on the visible region (no MKMapView needed).
enum GymClusterer {
    static func clusters(for gyms: [Gym], region: MKCoordinateRegion) -> [GymCluster] {
        let cellLat = max(region.span.latitudeDelta / 7, 0.0005)
        let cellLon = max(region.span.longitudeDelta / 5, 0.0005)
        var buckets: [String: [Gym]] = [:]
        var order: [String] = []
        for gym in gyms {
            let row = Int((gym.latitude / cellLat).rounded(.down))
            let col = Int((gym.longitude / cellLon).rounded(.down))
            let key = "\(row):\(col)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(gym)
        }
        return order.compactMap { key in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            let lat = items.map { $0.latitude }.reduce(0, +) / Double(items.count)
            let lon = items.map { $0.longitude }.reduce(0, +) / Double(items.count)
            let id = items.count == 1 ? items[0].id.uuidString : key
            return GymCluster(id: id, gyms: items, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
}

struct RatingStarsView: View {
    let rating: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: starName(index))
                    .font(.system(size: size))
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private func starName(_ index: Int) -> String {
        let value = Double(index)
        if rating >= value { return "star.fill" }
        if rating >= value - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct LocationMissingBadge: View {
    var body: some View {
        Label("explore.locationMissing", systemImage: "mappin.slash")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.18)))
            .foregroundStyle(Color.orange)
    }
}

/// Card used in the map carousel and list.
struct GymCardView: View {
    let gym: Gym
    let cityName: String?
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                BeltAccent(verified: gym.verified)
                Text(gym.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let cityName {
                    Text(cityName)
                }
                if let affiliation = gym.affiliation {
                    Text(verbatim: "·")
                    Text(affiliation).lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let average = gym.ratingAverage, gym.ratingCount > 0 {
                    RatingStarsView(rating: average)
                    Text(verbatim: "\(String(format: "%.1f", average)) (\(gym.ratingCount))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("reviews.none")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !gym.hasCoordinates {
                    LocationMissingBadge()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

struct CityChipsView: View {
    let cities: [City]
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: Text("explore.allCities"), isOn: selection == nil) {
                    selection = nil
                }
                ForEach(cities) { city in
                    chip(title: Text(city.localizedName), isOn: selection == city.id) {
                        selection = city.id
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? Color.accentColor : Color(uiColor: .secondarySystemFill)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
