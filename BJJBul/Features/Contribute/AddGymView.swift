import SwiftUI
import MapKit
import CoreLocation

/// Two steps: 1) place the pin, 2) short form. Submits a pending gym_submissions row.
struct AddGymView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var affiliation = ""
    @State private var phone = ""
    @State private var instagram = ""
    @State private var website = ""
    @State private var city = ""
    @State private var address = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    ContentUnavailableView {
                        Label("contribute.thanks", systemImage: "checkmark.circle")
                    } description: {
                        Text("contribute.thanks.detail")
                    }
                } else if coordinate == nil {
                    LocationPickerView(initialCoordinate: nil, confirmTitle: "contribute.usePin") { picked in
                        coordinate = picked
                        Task { await reverseGeocode(picked) }
                    }
                } else {
                    form
                }
            }
            .navigationTitle("contribute.addGym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey(submitted ? "common.close" : "common.cancel")) { dismiss() }
                }
                if coordinate != nil && !submitted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("contribute.submit") {
                            Task { await submit() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("contribute.section.gym") {
                TextField("contribute.name", text: $name)
                TextField("contribute.affiliation", text: $affiliation)
            }
            Section("contribute.section.contact") {
                TextField("contribute.phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("contribute.instagram", text: $instagram)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("contribute.website", text: $website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("contribute.section.location") {
                TextField("contribute.city", text: $city)
                TextField("contribute.address", text: $address)
                Button("contribute.changePin") {
                    coordinate = nil
                }
            }
            Section {
            } footer: {
                Text("contribute.reviewNote")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    @MainActor
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let placemark = placemarks.first else { return }
        if city.isEmpty {
            city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
        }
        if address.isEmpty {
            address = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        }
    }

    @MainActor
    private func submit() async {
        guard let coordinate else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let draft = GymSubmissionDraft(kind: .newGym, gymId: nil,
                                       name: name.trimmingCharacters(in: .whitespaces),
                                       affiliation: affiliation, phone: phone, instagram: instagram,
                                       website: website, city: city, address: address,
                                       latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            try await services.contributions.submitGym(draft)
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// "Fix location" for an existing gym: pick a pin, submit a location_fix suggestion.
struct FixLocationView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gym: Gym
    @State private var submitted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    ContentUnavailableView {
                        Label("contribute.thanks", systemImage: "checkmark.circle")
                    } description: {
                        Text("contribute.thanks.detail")
                    }
                } else {
                    VStack(spacing: 0) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                        LocationPickerView(initialCoordinate: gym.hasCoordinates ? gym.coordinate : nil,
                                           confirmTitle: "contribute.submitLocation") { picked in
                            Task { await submit(picked) }
                        }
                    }
                }
            }
            .navigationTitle("contribute.fixLocation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey(submitted ? "common.close" : "common.cancel")) { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func submit(_ coordinate: CLLocationCoordinate2D) async {
        var address = gym.address
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first {
            let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            if !street.isEmpty { address = street }
        }
        let draft = GymSubmissionDraft(kind: .locationFix, gymId: gym.id, name: "", affiliation: "",
                                       phone: "", instagram: "", website: "", city: "", address: address,
                                       latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            try await services.contributions.submitGym(draft)
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
