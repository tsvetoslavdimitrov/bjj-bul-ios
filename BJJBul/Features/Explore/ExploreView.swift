import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(AppServices.self) private var services
    @State private var gyms: [Gym] = []
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 42.7, longitude: 25.3),
            span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 6.0)
        )
    )

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(gyms.filter { $0.hasCoordinates }) { gym in
                    Marker(gym.name, coordinate: CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude))
                }
            }
            .navigationTitle("tab.explore")
            .task {
                gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
            }
        }
    }
}
