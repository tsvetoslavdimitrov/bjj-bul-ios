import SwiftUI
import MapKit

struct GymMapView: View {
    let gyms: [Gym]
    let focusCity: City?
    let cityName: (UUID) -> String?
    let missingCount: Int
    let onShowList: () -> Void

    static let bulgaria = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.75, longitude: 25.3),
        span: MKCoordinateSpan(latitudeDelta: 3.4, longitudeDelta: 5.8)
    )

    @State private var position: MapCameraPosition = .region(GymMapView.bulgaria)
    @State private var region: MKCoordinateRegion = GymMapView.bulgaria
    @State private var selectedId: UUID?
    @State private var location = LocationManager()
    @State private var wantsNearMe = false

    private var clusters: [GymCluster] {
        GymClusterer.clusters(for: gyms, region: region)
    }

    private var showsLabels: Bool {
        region.span.latitudeDelta < 0.35
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                UserAnnotation()
                ForEach(clusters) { cluster in
                    Annotation(cluster.gyms.count == 1 ? cluster.gyms[0].name : "",
                               coordinate: cluster.coordinate, anchor: .bottom) {
                        annotationContent(cluster)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
            }

            VStack(spacing: 10) {
                HStack {
                    if missingCount > 0 {
                        Button(action: onShowList) {
                            Label("explore.missingOnMap \(missingCount)", systemImage: "mappin.slash")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    nearMeButton
                }
                .padding(.horizontal)
                if !gyms.isEmpty {
                    carousel
                }
            }
            .padding(.bottom, 12)
        }
        .onChange(of: focusCity?.id) { _, _ in
            focusOnCity()
        }
        .onChange(of: selectedId) { _, newValue in
            moveCamera(to: newValue)
        }
        .onChange(of: location.lastLocation) { _, newValue in
            guard wantsNearMe, let newValue else { return }
            wantsNearMe = false
            withAnimation {
                position = .region(MKCoordinateRegion(center: newValue.coordinate,
                                                      span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
            }
        }
        .onAppear {
            focusOnCity()
        }
    }

    @ViewBuilder
    private func annotationContent(_ cluster: GymCluster) -> some View {
        if cluster.gyms.count == 1 {
            let gym = cluster.gyms[0]
            GymPinView(gym: gym, isSelected: gym.id == selectedId, showsLabel: showsLabels)
                .onTapGesture {
                    selectedId = gym.id
                }
        } else {
            ClusterBubble(count: cluster.gyms.count)
                .onTapGesture {
                    zoom(into: cluster)
                }
        }
    }

    private var nearMeButton: some View {
        Button {
            wantsNearMe = true
            location.request()
        } label: {
            Image(systemName: location.isDenied ? "location.slash" : "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("explore.nearMe"))
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(gyms) { gym in
                    NavigationLink(value: gym) {
                        GymCardView(gym: gym, cityName: cityName(gym.cityId), isSelected: gym.id == selectedId)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 280)
                    .id(gym.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedId)
        .frame(height: 110)
    }

    private func moveCamera(to gymId: UUID?) {
        guard let gymId, let gym = gyms.first(where: { $0.id == gymId }) else { return }
        let span = MKCoordinateSpan(latitudeDelta: min(region.span.latitudeDelta, 0.08),
                                    longitudeDelta: min(region.span.longitudeDelta, 0.08))
        withAnimation {
            position = .region(MKCoordinateRegion(center: gym.coordinate, span: span))
        }
    }

    private func zoom(into cluster: GymCluster) {
        let lats = cluster.gyms.map { $0.latitude }
        let lons = cluster.gyms.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.02),
                                    longitudeDelta: max((maxLon - minLon) * 1.8, 0.02))
        withAnimation {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func focusOnCity() {
        guard let city = focusCity else {
            withAnimation { position = .region(GymMapView.bulgaria) }
            return
        }
        let inCity = gyms.filter { $0.cityId == city.id }
        if let first = inCity.first {
            let cluster = GymCluster(id: "city", gyms: inCity, coordinate: first.coordinate)
            if inCity.count == 1 {
                withAnimation {
                    position = .region(MKCoordinateRegion(center: first.coordinate,
                                                          span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
                }
            } else {
                zoom(into: cluster)
            }
        }
    }
}
