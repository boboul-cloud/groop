//
//  PlusExportationView.swift
//  coquilles
//
//  Export PDF, bons de commande et fiches de distribution.
//

import SwiftUI
import QuickLook

struct PlusExportationView: View {
    @ObservedObject var store: OrderStore

    @State private var shareItem: IdentifiableURL? = nil
    @State private var previewURL: URL? = nil
    @State private var showExportFeedback = false
    @State private var showConfirmFinie = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                finalisationSection
                exportSection
                bonCommandeSection
                distributionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Exportation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .quickLookPreview($previewURL)
        .alert("Générer le récapitulatif final ?", isPresented: $showConfirmFinie) {
            Button("Générer et partager") {
                if let url = store.exporterRecapitulatif() {
                    shareItem = IdentifiableURL(url: url)
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: - Finalisation

    @ViewBuilder
    private var finalisationSection: some View {
        if store.toutEstFini {
            VStack(spacing: 12) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.seafoam)
                    .symbolEffect(.bounce.up, value: true)

                Text("Toutes les commandes sont finalisées !")
                    .font(.headline)
                    .foregroundStyle(.seafoam)
                    .multilineTextAlignment(.center)

                Button {
                    showConfirmFinie = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Générer le récapitulatif final")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.seafoam.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
            .background(Color.seafoam.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Export PDF

    private var exportSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.ocean)
                Text("Export PDF")
                    .font(.headline)
                    .foregroundStyle(.ocean)
                Spacer()
            }

            Button {
                if let url = store.exporterRecapitulatif() {
                    previewURL = url
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Consulter le récapitulatif")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.ocean.opacity(0.1))
                .foregroundStyle(.ocean)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                if let url = store.exporterRecapitulatif() {
                    shareItem = IdentifiableURL(url: url)
                    showExportFeedback = true
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Partager le récapitulatif")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient.oceanGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Bon de commande

    private var bonCommandeSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "list.clipboard.fill")
                    .foregroundStyle(.ocean)
                Text("Bon de commande")
                    .font(.headline)
                    .foregroundStyle(.ocean)
                Spacer()
            }

            Text("Regroupe toutes les commandes par variante, taille et couleur")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            BonCommandeButton(
                icon: "doc.text.magnifyingglass",
                label: "Détaillé (prix + clients)",
                style: .outline
            ) {
                if let url = store.exporterBonCommande(afficherPrix: true, afficherClients: true) {
                    previewURL = url
                }
            }

            BonCommandeButton(
                icon: "eurosign.circle",
                label: "Avec prix, sans clients",
                style: .outline
            ) {
                if let url = store.exporterBonCommande(afficherPrix: true, afficherClients: false) {
                    previewURL = url
                }
            }

            BonCommandeButton(
                icon: "shippingbox",
                label: "Fournisseur (quantités seules)",
                style: .outline
            ) {
                if let url = store.exporterBonCommande(afficherPrix: false, afficherClients: false) {
                    previewURL = url
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Distribution

    private var distributionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "truck.box.fill")
                    .foregroundStyle(.ocean)
                Text("Fiche de distribution")
                    .font(.headline)
                    .foregroundStyle(.ocean)
                Spacer()
            }

            Text("Liste par catégorie et par client pour la distribution, avec cases à cocher")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            BonCommandeButton(
                icon: "doc.text.magnifyingglass",
                label: "Consulter",
                style: .outline
            ) {
                if let url = store.exporterDistribution() {
                    previewURL = url
                }
            }

            BonCommandeButton(
                icon: "square.and.arrow.up",
                label: "Partager",
                style: .filled
            ) {
                if let url = store.exporterDistribution() {
                    shareItem = IdentifiableURL(url: url)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Bouton bon de commande

struct BonCommandeButton: View {
    enum Style { case outline, filled }

    let icon: String
    let label: String
    var style: Style = .outline
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(style == .filled ? AnyShapeStyle(LinearGradient.seaGradient) : AnyShapeStyle(Color.ocean.opacity(0.1)))
            .foregroundStyle(style == .filled ? .white : .ocean)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
