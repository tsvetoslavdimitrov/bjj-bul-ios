import SwiftUI

extension View {
    /// Shows report reasons for the given target and files the report.
    func reportDialog(target: Binding<ReportTarget?>, services: AppServices,
                      onReported: @escaping () -> Void = {}) -> some View {
        let isPresented = Binding<Bool>(
            get: { target.wrappedValue != nil },
            set: { newValue in
                if !newValue { target.wrappedValue = nil }
            }
        )
        return confirmationDialog("report.title", isPresented: isPresented,
                                  titleVisibility: .visible, presenting: target.wrappedValue) { item in
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(LocalizedStringKey(reason.localizedKey), role: .destructive) {
                    Task {
                        try? await services.social.report(item, reason: reason)
                        onReported()
                    }
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: { _ in
            Text("report.message")
        }
    }
}
