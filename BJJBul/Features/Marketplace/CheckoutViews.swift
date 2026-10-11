import SwiftUI

struct CartView: View {
    @Environment(AppServices.self) private var services

    private var partnerIds: [UUID] {
        var seen: [UUID] = []
        for item in services.cart where !seen.contains(item.product.partnerId) {
            seen.append(item.product.partnerId)
        }
        return seen
    }

    var body: some View {
        List {
            if services.cart.isEmpty {
                ContentUnavailableView("shop.cart.empty", systemImage: "cart")
            }
            ForEach(partnerIds, id: \.self) { partnerId in
                Section {
                    ForEach(items(for: partnerId)) { item in
                        cartRow(item)
                    }
                    HStack {
                        Text("shop.total")
                        Spacer()
                        Text(PriceText.eur(total(for: partnerId))).bold()
                    }
                    NavigationLink {
                        CheckoutView(partnerId: partnerId)
                    } label: {
                        Label("shop.checkout", systemImage: "creditcard")
                    }
                } header: {
                    Text(items(for: partnerId).first?.product.partnerName ?? "")
                }
            }
        }
        .navigationTitle("shop.cart")
    }

    private func items(for partnerId: UUID) -> [CartItem] {
        services.cart.filter { $0.product.partnerId == partnerId }
    }

    private func total(for partnerId: UUID) -> Double {
        items(for: partnerId).reduce(0) { $0 + $1.lineTotal }
    }

    private func cartRow(_ item: CartItem) -> some View {
        HStack(spacing: 12) {
            ProductImageView(url: item.product.imageURLs.first, category: item.product.category, height: 56)
                .frame(width: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title(bulgarian: ShopLocale.isBulgarian)).font(.subheadline)
                if let size = item.size {
                    Text(size).font(.caption).foregroundStyle(.secondary)
                }
                Text(PriceText.eur(item.lineTotal)).font(.caption.bold())
            }
            Spacer()
            Stepper("", value: qtyBinding(item), in: 0...20)
                .labelsHidden()
        }
    }

    private func qtyBinding(_ item: CartItem) -> Binding<Int> {
        Binding(
            get: { services.cart.first { $0.id == item.id }?.qty ?? 0 },
            set: { newValue in
                if newValue <= 0 {
                    services.cart.removeAll { $0.id == item.id }
                } else if let index = services.cart.firstIndex(where: { $0.id == item.id }) {
                    services.cart[index].qty = newValue
                }
            }
        )
    }
}

struct CheckoutView: View {
    @Environment(AppServices.self) private var services
    let partnerId: UUID

    @State private var draft = CheckoutDraft()
    @State private var partner: Partner?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var placed: MarketplaceOrder?

    private var items: [CartItem] { services.cart.filter { $0.product.partnerId == partnerId } }
    private var total: Double { items.reduce(0) { $0 + $1.lineTotal } }

    var body: some View {
        Group {
            if let placed {
                OrderPlacedView(order: placed, partner: partner)
            } else {
                form
            }
        }
        .navigationTitle("shop.checkout")
        .task {
            partner = try? await services.marketplace.partner(id: partnerId)
            if draft.shippingName.isEmpty, let name = services.currentUser?.displayName {
                draft.shippingName = name
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(items) { item in
                    HStack {
                        Text("\(item.qty) × \(item.product.title(bulgarian: ShopLocale.isBulgarian))")
                        Spacer()
                        Text(PriceText.eur(item.lineTotal))
                    }
                    .font(.subheadline)
                }
                HStack {
                    Text("shop.total")
                    Spacer()
                    Text(PriceText.eur(total)).bold()
                }
            } header: {
                Text(partner?.name ?? "")
            }

            Section {
                TextField("order.name", text: $draft.shippingName)
                    .textContentType(.name)
                TextField("order.phone", text: $draft.shippingPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Picker("order.delivery", selection: $draft.deliveryType) {
                    ForEach(DeliveryType.allCases, id: \.self) { type in
                        Text(LocalizedStringKey(type.localizedKey)).tag(type)
                    }
                }
                TextField(addressPrompt, text: $draft.shippingAddress, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("order.shipping")
            }

            Section {
                Picker("order.payment", selection: $draft.paymentMethod) {
                    ForEach(OrderPaymentMethod.allCases, id: \.self) { method in
                        Text(LocalizedStringKey(method.localizedKey)).tag(method)
                    }
                }
                TextField("order.notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(1...4)
                Text("order.privacy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("order.paymentSection")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await placeOrder() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("order.send").bold()
                    }
                }
                .disabled(!draft.isValid || items.isEmpty || isSending || !services.isSignedIn)
                if !services.isSignedIn {
                    Text("shop.signInRequired").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var addressPrompt: LocalizedStringKey {
        switch draft.deliveryType {
        case .econtOffice: return "order.address.econt"
        case .speedyOffice: return "order.address.speedy"
        case .address: return "order.address.home"
        }
    }

    @MainActor
    private func placeOrder() async {
        isSending = true
        defer { isSending = false }
        do {
            let order = try await services.marketplace.placeOrder(partnerId: partnerId, items: items, draft: draft)
            services.clearCart(partnerId: partnerId)
            placed = order
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shown after an order request: reference, Revolut link / cash instructions.
struct OrderPlacedView: View {
    let order: MarketplaceOrder
    let partner: Partner?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Label("order.placed", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("order.placed.note").font(.subheadline)
                if let reference = order.reference {
                    HStack {
                        Text("order.reference")
                        Spacer()
                        Text(reference).font(.body.monospaced()).textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = reference
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Text("shop.total")
                    Spacer()
                    Text(PriceText.eur(order.totalEUR)).bold()
                }
            }
            Section {
                switch order.paymentMethod {
                case .revolut:
                    if let url = partner?.revolutURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("order.payRevolut", systemImage: "arrow.up.right.square")
                        }
                        Text("order.revolut.note").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("order.revolut.missing").font(.footnote)
                    }
                case .cash:
                    Text("order.cash.note").font(.footnote)
                case .card:
                    Text("order.card.note").font(.footnote)
                }
            } header: {
                Text("order.howToPay")
            }
        }
    }
}

struct MyOrdersView: View {
    @Environment(AppServices.self) private var services
    @State private var orders: [MarketplaceOrder] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if !isLoading && orders.isEmpty {
                ContentUnavailableView("shop.myOrders.empty", systemImage: "shippingbox")
            }
            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(order.partnerName).font(.headline)
                        Spacer()
                        OrderStatusBadge(status: order.status)
                    }
                    Text(order.items.map { "\($0.qty) × \($0.title)" }.joined(separator: ", "))
                        .font(.subheadline)
                    HStack {
                        Text(BGDate.string(order.createdAt, date: .medium, time: .none))
                        Spacer()
                        Text(PriceText.eur(order.totalEUR)).bold()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let reference = order.reference {
                        Text(reference).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if order.status == .requested {
                        Button("order.cancel", role: .destructive) {
                            Task { await cancel(order) }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("shop.myOrders")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        orders = (try? await services.marketplace.myOrders()) ?? []
        isLoading = false
    }

    @MainActor
    private func cancel(_ order: MarketplaceOrder) async {
        try? await services.marketplace.cancelOrder(id: order.id)
        await load()
    }
}

struct OrderStatusBadge: View {
    let status: OrderStatus

    private var color: Color {
        switch status {
        case .requested: return .orange
        case .confirmed: return .blue
        case .paid: return .teal
        case .shipped: return .indigo
        case .completed: return .green
        case .cancelled: return .gray
        }
    }

    var body: some View {
        Text(LocalizedStringKey(status.localizedKey))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
