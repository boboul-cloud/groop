//
//  PaiementsView.swift
//  Groop
//
//  Vue des paiements avec graphiques visuels et résumé.
//

import SwiftUI

struct PaiementsView: View {
    @ObservedObject var store: OrderStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Barre de progression
                    VStack(spacing: 8) {
                        HStack {
                            Text("Progression des paiements")
                                .font(.headline)
                                .foregroundStyle(.ocean)
                            Spacer()
                            Text(String(format: "%.0f%%", progressionPaiement * 100))
                                .font(.headline)
                                .foregroundStyle(.ocean)
                                .contentTransition(.numericText())
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.ocean.opacity(0.1))
                                    .frame(height: 12)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient.oceanGradient)
                                    .frame(width: max(0, geo.size.width * progressionPaiement), height: 12)
                                    .animation(.spring(response: 0.8), value: progressionPaiement)
                            }
                        }
                        .frame(height: 12)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // MARK: - Cartes de paiement
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        PaymentCard(
                            title: "Chèques",
                            amount: store.totalCheque,
                            count: store.nombreCheques,
                            icon: "doc.plaintext.fill",
                            color: .oceanLight
                        )
                        PaymentCard(
                            title: "Espèces",
                            amount: store.totalEspeces,
                            count: store.nombreEspeces,
                            icon: "banknote.fill",
                            color: .seafoam
                        )
                    }

                    // MARK: - Résumé
                    VStack(spacing: 12) {
                        SummaryItem(
                            icon: "checkmark.circle.fill",
                            iconColor: .seafoam,
                            label: "Commandes réglées",
                            value: "\(store.nombreRegles)"
                        )
                        Divider()
                        SummaryItem(
                            icon: "clock.fill",
                            iconColor: .orange,
                            label: "Non réglées",
                            value: "\(store.nombreNonRegles)"
                        )
                        Divider()
                        SummaryItem(
                            icon: "eurosign.circle.fill",
                            iconColor: .ocean,
                            label: "Total réglé",
                            value: String(format: "%.2f €", store.totalPaye)
                        )
                        Divider()
                        SummaryItem(
                            icon: "cart.fill",
                            iconColor: .oceanLight,
                            label: "Total général",
                            value: String(format: "%.2f €", store.totalGeneral)
                        )
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // MARK: - Impayés
                    if store.totalImpayes > 0 {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.coral)
                                    .symbolEffect(.pulse)
                                Text("Livrés, non réglés")
                                    .font(.headline)
                                    .foregroundStyle(.coral)
                                Spacer()
                            }
                            Divider()

                            HStack {
                                Text("Client")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Livré")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                                Text("Réglé")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                            }

                            ForEach(store.orders.filter { ($0.estLivre || $0.partiellementLivre) && $0.resteARegler(variantes: store.variantes) > 0 }) { order in
                                let montantLivre = order.totalLivre(variantes: store.variantes)
                                let montantRegle = order.totalRegle
                                let couleur: Color = montantLivre > montantRegle ? .coral : .orange
                                HStack {
                                    Text(order.nomComplet.isEmpty ? "Sans nom" : order.nomComplet)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(String(format: "%.2f €", montantLivre))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(couleur)
                                        .frame(width: 70, alignment: .trailing)
                                    Text(String(format: "%.2f €", montantRegle))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(couleur)
                                        .frame(width: 70, alignment: .trailing)
                                }
                            }
                            Divider()
                            HStack {
                                Text("Total impayés")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(String(format: "%.2f €", store.totalImpayes))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.coral)
                            }
                        }
                        .padding()
                        .background(Color.coral.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // MARK: - Manque
                    HStack(spacing: 16) {
                        Image(systemName: store.manque > 0 ? "exclamationmark.circle.fill" : "checkmark.seal.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(store.manque > 0 ? .coral : .seafoam)
                            .symbolEffect(.bounce, value: store.manque)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reste à encaisser")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f €", store.manque))
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(store.manque > 0 ? .coral : .seafoam)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                    }
                    .padding()
                    .background(store.manque > 0 ? Color.coral.opacity(0.08) : Color.seafoam.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Paiements")
        }
    }

    private var progressionPaiement: CGFloat {
        guard store.totalGeneral > 0 else { return 0 }
        return min(1, CGFloat(store.totalPaye / store.totalGeneral))
    }
}

// MARK: - Carte de paiement

struct PaymentCard: View {
    let title: String
    let amount: Double
    let count: Int
    let icon: String
    let color: Color

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.gradient)
                    .clipShape(Capsule())
            }
            Text(String(format: "%.2f €", amount))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Ligne résumé avec icône

struct SummaryItem: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}
