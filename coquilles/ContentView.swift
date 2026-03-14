//
//  ContentView.swift
//  coquilles
//
//  Created by Robert Oulhen on 11/03/2026.
//

import SwiftUI
import MessageUI
import QuickLook

struct ContentView: View {
    @ObservedObject var store: OrderStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(store: store)
                .tabItem {
                    Label("Tableau", systemImage: "chart.bar.fill")
                }
                .tag(0)

            CommandesView(store: store)
                .tabItem {
                    Label("Commandes", systemImage: "list.clipboard.fill")
                }
                .tag(1)
                .badge(store.nombreNonRegles > 0 ? store.nombreNonRegles : 0)

            PaiementsView(store: store)
                .tabItem {
                    Label("Paiements", systemImage: "creditcard.fill")
                }
                .tag(2)

            MessagesExportView(store: store)
                .tabItem {
                    Label("Plus", systemImage: "ellipsis.circle.fill")
                }
                .tag(3)
        }
        .tint(.ocean)
    }
}

// MARK: - SMS Compose
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) private var dismiss

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}

// MARK: - Identifiable URL
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView(store: OrderStore())
}
