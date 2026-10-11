import SwiftUI
import PhotosUI

struct BecomePartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var application = PartnerApplication()
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !application.name.trimmingCharacters(in: .whitespaces).isEmpty
            && application.contactEmail.contains("@")
    }

    var body: some View {
        Form {
            Section {
                Text("partner.become.intro").font(.subheadline)
            }
            Section {
                TextField("partner.name", text: $application.name)
                TextField("partner.website", text: $application.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("partner.email", text: $application.contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("partner.description", text: $application.description, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("partner.become.details")
            }
            Section {
                Text("partner.become.terms").font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            Section {
                if sent {
                    Label("partner.become.sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSending { ProgressView() } else { Text("partner.become.submit").bold() }
                    }
                    .disabled(!isValid || isSending || !services.isSignedIn)
                    if !services.isSignedIn {
                        Text("shop.signInRequired").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("partner.become")
    }

    @MainActor
    private func submit() async {
        isSending = true
        defer { isSending = false }
        do {
            try await services.marketplace.applyAsPartner(application)
            sent = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MyPartnerStoresView: View {
    @Environment(AppServices.self) private var services
    @State private var partners: [Partner] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if !isLoading && partners.isEmpty {
                Section {
                    Text("partner.none").font(.subheadline)
                    NavigationLink {
                        BecomePartnerView()
                    } label: {
                        Label("partner.become", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            ForEach(partners) { partner in
                if partner.role == "applicant" || partner.status != .approved {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(partner.name).font(.headline)
                        Text("partner.pendingReview").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    NavigationLink {
                        PartnerDashboardView(partner: partner)
                    } label: {
                        Label(partner.name, systemImage: "storefront")
                    }
                }
            }
        }
        .navigationTitle("partner.myStore")
        .task {
            partners = (try? await services.marketplace.myPartners()) ?? []
            isLoading = false
        }
    }
}

struct PartnerDashboardView: View {
    @Environment(AppServices.self) private var services
    let partner: Partner

    @State private var ledger: [LedgerMonth] = []
    @State private var orders: [MarketplaceOrder] = []
    @State private var productCount = 0

    private var thisMonth: LedgerMonth? { ledger.first }
    private var openOrders: Int {
        orders.filter { $0.status == .requested || $0.status == .confirmed || $0.status == .paid }.count
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    kpi("partner.kpi.sales", PriceText.eur(thisMonth?.salesEUR ?? 0))
                    kpi("partner.kpi.commission", PriceText.eur(thisMonth?.commissionEUR ?? 0))
                    kpi("partner.kpi.openOrders", "\(openOrders)")
                    kpi("partner.kpi.clicks", "\(thisMonth?.clicks ?? 0)")
                }
                .padding(.vertical, 4)
            } header: {
                Text("partner.thisMonth")
            }
            Section {
                NavigationLink {
                    PartnerProductsView(partner: partner)
                } label: {
                    Label("partner.products", systemImage: "tag")
                        .badge(productCount)
                }
                NavigationLink {
                    PartnerOrdersView(partner: partner)
                } label: {
                    Label("partner.orders", systemImage: "shippingbox")
                        .badge(openOrders)
                }
                NavigationLink {
                    PartnerLedgerView(partner: partner)
                } label: {
                    Label("partner.ledger", systemImage: "chart.bar")
                }
            }
            Section {
                Text(String(format: NSLocalizedString("partner.commissionInfo %@", comment: ""),
                            String(format: "%.0f%%", partner.commissionPct)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(partner.name)
        .task { await load() }
        .refreshable { await load() }
    }

    private func kpi(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func load() async {
        ledger = (try? await services.marketplace.ledger(partnerId: partner.id)) ?? []
        orders = (try? await services.marketplace.partnerOrders(partnerId: partner.id)) ?? []
        productCount = ((try? await services.marketplace.products(partnerId: partner.id)) ?? []).count
    }
}

struct PartnerProductsView: View {
    @Environment(AppServices.self) private var services
    let partner: Partner
    @State private var products: [Product] = []
    @State private var editing: Product?

    var body: some View {
        List {
            if products.isEmpty {
                Text("partner.products.empty").foregroundStyle(.secondary)
            }
            ForEach(products) { product in
                Button {
                    editing = product
                } label: {
                    HStack(spacing: 12) {
                        ProductImageView(url: product.imageURLs.first, category: product.category, height: 48)
                            .frame(width: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.title(bulgarian: ShopLocale.isBulgarian)).foregroundStyle(.primary)
                            Text(PriceText.eur(product.priceEUR)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !product.active {
                            Text("partner.product.hidden").font(.caption2).foregroundStyle(.secondary)
                        } else if let stock = product.stock {
                            Text(String(format: NSLocalizedString("partner.stock %lld", comment: ""), stock))
                                .font(.caption2)
                                .foregroundStyle(stock > 0 ? Color.secondary : Color.red)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { products[$0].id }
                Task {
                    for id in ids {
                        try? await services.marketplace.deleteProduct(id: id)
                    }
                    await load()
                }
            }
        }
        .navigationTitle("partner.products")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = Product.new(partnerId: partner.id)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { product in
            ProductEditorView(partner: partner, product: product) {
                Task { await load() }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        products = (try? await services.marketplace.products(partnerId: partner.id)) ?? []
    }
}

struct ProductEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let partner: Partner
    let onSaved: () -> Void

    @State private var product: Product
    @State private var priceText: String
    @State private var compareText: String
    @State private var stockText: String
    @State private var sizesText: String
    @State private var urlText: String
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(partner: Partner, product: Product, onSaved: @escaping () -> Void) {
        self.partner = partner
        self.onSaved = onSaved
        _product = State(initialValue: product)
        _priceText = State(initialValue: product.priceEUR > 0 ? String(format: "%.2f", product.priceEUR) : "")
        _compareText = State(initialValue: product.compareAtPrice.map { String(format: "%.2f", $0) } ?? "")
        _stockText = State(initialValue: product.stock.map { String($0) } ?? "")
        _sizesText = State(initialValue: product.sizes.joined(separator: ", "))
        _urlText = State(initialValue: product.externalURL?.absoluteString ?? "")
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var isValid: Bool {
        guard !product.titleBg.trimmingCharacters(in: .whitespaces).isEmpty, let price = number(priceText), price >= 0 else {
            return false
        }
        if product.fulfillment == .affiliateLink {
            return urlText.hasPrefix("https://")
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("partner.product.titleBg", text: $product.titleBg)
                    TextField("partner.product.titleEn", text: optionalBinding(\.titleEn))
                    Picker("partner.product.category", selection: $product.category) {
                        ForEach(ProductCategory.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                } header: {
                    Text("partner.product.basics")
                }
                Section {
                    TextField("partner.product.price", text: $priceText).keyboardType(.decimalPad)
                    TextField("partner.product.compareAt", text: $compareText).keyboardType(.decimalPad)
                    TextField("partner.product.stock", text: $stockText).keyboardType(.numberPad)
                    TextField("partner.product.sizes", text: $sizesText)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("partner.product.pricing")
                }
                Section {
                    Picker("partner.product.fulfillment", selection: $product.fulfillment) {
                        ForEach(Fulfillment.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    TextField("partner.product.url", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Toggle("partner.product.active", isOn: $product.active)
                } header: {
                    Text("partner.product.selling")
                }
                Section {
                    TextField("partner.product.descBg", text: optionalBinding(\.descriptionBg), axis: .vertical)
                        .lineLimit(3...8)
                    TextField("partner.product.descEn", text: optionalBinding(\.descriptionEn), axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("partner.product.description")
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(product.imageURLs, id: \.self) { url in
                                ProductImageView(url: url, category: product.category, height: 72)
                                    .frame(width: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            product.imageURLs.removeAll { $0 == url }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                            }
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("partner.product.addPhoto", systemImage: "photo.badge.plus")
                    }
                    .disabled(product.imageURLs.count >= 6)
                } header: {
                    Text("partner.product.photos")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("partner.product.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onChange(of: photoItem) { _, item in
                if let item {
                    Task { await upload(item) }
                }
            }
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<Product, String?>) -> Binding<String> {
        Binding(
            get: { product[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                product[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    @MainActor
    private func upload(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ImageCompressor.jpegData(from: data) else { return }
            let url = try await services.marketplace.uploadProductImage(partnerId: partner.id, jpegData: jpeg)
            product.imageURLs.append(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var item = product
        item.priceEUR = number(priceText) ?? 0
        item.compareAtPrice = number(compareText)
        item.stock = Int(stockText.trimmingCharacters(in: .whitespaces))
        item.sizes = sizesText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedURL = urlText.trimmingCharacters(in: .whitespaces)
        item.externalURL = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
        do {
            try await services.marketplace.saveProduct(item)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PartnerOrdersView: View {
    @Environment(AppServices.self) private var services
    let partner: Partner
    @State private var orders: [MarketplaceOrder] = []

    var body: some View {
        List {
            if orders.isEmpty {
                Text("partner.orders.empty").foregroundStyle(.secondary)
            }
            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(order.reference ?? "").font(.subheadline.monospaced())
                        Spacer()
                        OrderStatusBadge(status: order.status)
                    }
                    ForEach(Array(order.items.enumerated()), id: \.offset) { _, item in
                        Text(verbatim: lineText(item))
                            .font(.subheadline)
                    }
                    Text("\(order.shippingName) · \(order.shippingPhone)").font(.caption)
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(order.deliveryType.localizedKey))
                        Text("· \(order.shippingAddress)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let notes = order.notes, !notes.isEmpty {
                        Text(notes).font(.caption).italic()
                    }
                    HStack {
                        Text(LocalizedStringKey(order.paymentMethod.localizedKey)).font(.caption)
                        Spacer()
                        Text(PriceText.eur(order.totalEUR)).bold()
                    }
                    HStack {
                        if let next = order.status.next {
                            Button {
                                Task { await setStatus(order, next) }
                            } label: {
                                Text(LocalizedStringKey("order.markAs." + next.rawValue))
                            }
                            .buttonStyle(.bordered)
                        }
                        if order.status != .cancelled && order.status != .completed {
                            Button("order.cancel", role: .destructive) {
                                Task { await setStatus(order, .cancelled) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("partner.orders")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        orders = (try? await services.marketplace.partnerOrders(partnerId: partner.id)) ?? []
    }

    private func lineText(_ item: OrderItem) -> String {
        var text = "\(item.qty) × " + item.title
        if let size = item.size, !size.isEmpty {
            text += " (" + size + ")"
        }
        return text
    }

    @MainActor
    private func setStatus(_ order: MarketplaceOrder, _ status: OrderStatus) async {
        try? await services.marketplace.setOrderStatus(orderId: order.id, status: status)
        await load()
    }
}

struct PartnerLedgerView: View {
    @Environment(AppServices.self) private var services
    let partner: Partner
    @State private var rows: [LedgerMonth] = []

    var body: some View {
        List {
            Section {
                Text("partner.ledger.note").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(EventDates.monthTitle(row.month)).font(.headline)
                    line("partner.ledger.orders", "\(row.orders)")
                    line("partner.ledger.clicks", "\(row.clicks)")
                    line("partner.ledger.sales", PriceText.eur(row.salesEUR))
                    line("partner.ledger.commission", PriceText.eur(row.commissionEUR))
                    line("partner.ledger.paid", PriceText.eur(row.paidEUR))
                    line("partner.ledger.owed", PriceText.eur(row.owedEUR))
                }
            }
        }
        .navigationTitle("partner.ledger")
        .task {
            rows = (try? await services.marketplace.ledger(partnerId: partner.id)) ?? []
        }
    }

    private func line(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}
