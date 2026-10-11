import SwiftUI
import MapKit

/// Pick a coordinate: drag the map under the centered pin, tap to jump there, or search an address.
struct LocationPickerView: View {
    let confirmTitle: LocalizedStringKey
    let onConfirm: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var span: MKCoordinateSpan
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchError: String?

    init(initialCoordinate: CLLocationCoordinate2D?, confirmTitle: LocalizedStringKey,
         onConfirm: @escaping (CLLocationCoordinate2D) -> Void) {
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        let start = initialCoordinate ?? CLLocationCoordinate2D(latitude: 42.6977, longitude: 23.3219)
        let delta = initialCoordinate == nil ? 0.15 : 0.01
        let startSpan = MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, span: startSpan)))
        _center = State(initialValue: start)
        _span = State(initialValue: startSpan)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !results.isEmpty {
                List(results, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "")
                            Text(item.placemark.title ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 220)
            }

            ZStack {
                MapReader { proxy in
                    Map(position: $position)
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .onMapCameraChange(frequency: .continuous) { context in
                            center = context.region.center
                            span = context.region.span
                        }
                        .onTapGesture { point in
                            if let coordinate = proxy.convert(point, from: .local) {
                                withAnimation {
                                    position = .region(MKCoordinateRegion(center: coordinate, span: span))
                                }
                            }
                        }
                }
                // Centered pin; the tip marks the selected point.
                Image(systemName: "mappin")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .shadow(radius: 2)
                    .offset(y: -20)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 8) {
                Text("contribute.pinHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    onConfirm(center)
                } label: {
                    Text(confirmTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var searchBar: some View {
        HStack {
            TextField("contribute.searchAddress", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    Task { await search() }
                }
            if isSearching {
                ProgressView()
            } else {
                Button {
                    Task { await search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    @MainActor
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 42.75, longitude: 25.3),
                                            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 7))
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = Array(response.mapItems.prefix(8))
            searchError = nil
        } catch {
            results = []
            searchError = error.localizedDescription
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        results = []
        withAnimation {
            position = .region(MKCoordinateRegion(center: coordinate,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        }
    }
}
