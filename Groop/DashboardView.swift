//
//  DashboardView.swift
//  Groop
//
//  Tableau de bord avec cartes animées et résumé visuel.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: OrderStore
    @ObservedObject var storeManager: StoreManager
    @State private var waveOffset: CGFloat = 0
    @State private var showProUpgrade = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - En-tête avec vagues
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient.oceanGradient
                            .frame(height: 180)

                        WaveShape(offset: waveOffset)
                            .fill(.white.opacity(0.15))
                            .frame(height: 60)
                            .offset(y: 30)

                        WaveShape(offset: waveOffset + 0.5)
                            .fill(.white.opacity(0.10))
                            .frame(height: 50)
                            .offset(y: 35)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.titreCampagne)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text("Tableau de bord")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 50)
                    }
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                            waveOffset = 1
                        }
                    }

                    VStack(spacing: 16) {
                        // MARK: - Prix
                        if !store.variantes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(store.variantes) { v in
                                        prixPill(label: v.nom, prix: v.prix)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }

                        // MARK: - Passage Pro
                        if !storeManager.proUnlocked {
                            Button {
                                showProUpgrade = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "star.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Passer à Groop Pro")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                        Text("Clients illimités, exports PDF, sauvegardes…")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .padding()
                                .background(LinearGradient(
                                    colors: [.orange, .yellow.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                            }
                        }

                        // MARK: - Cartes statistiques
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            StatCard(
                                title: "Quantité totale",
                                value: store.formatQte(store.totalQuantite),
                                icon: "scalemass.fill",
                                gradient: .oceanGradient
                            )
                            StatCard(
                                title: "Participants",
                                value: "\(store.nombreParticipants)",
                                icon: "person.2.fill",
                                gradient: .seaGradient
                            )
                            StatCard(
                                title: "Total général",
                                value: String(format: "%.2f €", store.totalGeneral),
                                icon: "eurosign.circle.fill",
                                gradient: .sunsetGradient
                            )
                            StatCard(
                                title: "Total réglé",
                                value: String(format: "%.2f €", store.totalPaye),
                                icon: "checkmark.circle.fill",
                                gradient: LinearGradient(
                                    colors: [.green, .seafoam],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }

                        // MARK: - Détail par variante
                        if !store.variantes.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(Array(store.variantes.enumerated()), id: \.element.id) { index, v in
                                    categorieCard(
                                        label: v.nom,
                                        quantite: store.quantitePourVariante(v.nom),
                                        commandes: store.nombreCommandesPourVariante(v.nom),
                                        total: store.totalPourVariante(v.nom),
                                        color: categorieColor(index: index)
                                    )
                                }
                            }
                        }

                        // MARK: - Stats par catégorie
                        if !store.categories.isEmpty {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.ocean)
                                    Text("Par catégorie")
                                        .font(.headline)
                                        .foregroundStyle(.ocean)
                                    Spacer()
                                }
                                ForEach(Array(store.categories.enumerated()), id: \.element.id) { index, cat in
                                    let ordresCat = store.orders.filter { $0.estValide && $0.categorieID == cat.id }
                                    let qteCat = ordresCat.flatMap(\.lignes).map(\.quantite).reduce(0, +)
                                    let totalCat = ordresCat.compactMap { $0.total(variantes: store.variantes) }.reduce(0, +)
                                    categorieCard(
                                        label: cat.nom.isEmpty ? "Sans nom" : cat.nom,
                                        quantite: qteCat,
                                        commandes: ordresCat.count,
                                        total: totalCat,
                                        color: categorieColor(index: index + store.variantes.count)
                                    )
                                }
                            }
                        }

                        // MARK: - Alerte impayés
                        if store.totalImpayes > 0 {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .symbolEffect(.pulse)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Impayés")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(String(format: "%.2f € — %d commande(s)", store.totalImpayes, store.nombreImpayes))
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.coral.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .coral.opacity(0.3), radius: 8, x: 0, y: 4)
                        }

                        // MARK: - Reste à livrer
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reste à livrer")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(store.resteALivrer) commande(s)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(store.resteALivrer > 0 ? .orange : .seafoam)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            Image(systemName: store.resteALivrer > 0 ? "shippingbox.fill" : "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(store.resteALivrer > 0 ? .orange : .seafoam)
                                .symbolEffect(.bounce, value: store.resteALivrer)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // MARK: - Manque
                        HStack {
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
                            Image(systemName: store.manque > 0 ? "arrow.down.circle.fill" : "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(store.manque > 0 ? .coral : .seafoam)
                                .symbolEffect(.bounce, value: store.manque)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // MARK: - Rappels
                        if !store.clientsImpayes.isEmpty {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.bubble.fill")
                                        .foregroundStyle(.coral)
                                    Text("\(store.clientsImpayes.count) impayé(s)")
                                        .font(.headline)
                                        .foregroundStyle(.coral)
                                    Spacer()
                                    Button {
                                        let noms = store.clientsImpayes.map(\.nomComplet).joined(separator: ", ")
                                        let corps = "Bonjour, merci de régulariser votre paiement pour la campagne \(store.titreCampagne). Cordialement."
                                        let nums = store.clientsImpayes.map(\.telephone).joined(separator: ",")
                                        if let url = URL(string: "sms:\(nums)&body=\(corps.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Relancer", systemImage: "message.fill")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.coral.gradient)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                                ForEach(store.clientsImpayes) { client in
                                    HStack {
                                        Text(client.nomComplet)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(String(format: "%.2f €", client.resteARegler(variantes: store.variantes)))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.coral)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.coral.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        if !store.clientsNonLivres.isEmpty {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.orange)
                                    Text("\(store.clientsNonLivres.count) à livrer")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Button {
                                        let corps = "Bonjour, votre commande \(store.titreCampagne) est prête ! Merci de venir la récupérer."
                                        let nums = store.clientsNonLivres.map(\.telephone).joined(separator: ",")
                                        if let url = URL(string: "sms:\(nums)&body=\(corps.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Prévenir", systemImage: "message.fill")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.gradient)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                                ForEach(store.clientsNonLivres.prefix(5)) { client in
                                    HStack {
                                        Text(client.nomComplet)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(store.formatQte(client.quantiteTotale))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if store.clientsNonLivres.count > 5 {
                                    Text("+ \(store.clientsNonLivres.count - 5) autre(s)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: $showProUpgrade) {
                GroopProView(storeManager: storeManager)
            }
        }
    }

    // MARK: - Pill prix

    private func prixPill(label: String, prix: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "eurosign.circle.fill")
                .foregroundStyle(.ocean)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f €/%@", prix, store.labelUnite))
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.ocean)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func categorieColor(index: Int) -> Color {
        let colors: [Color] = [.orange, .oceanLight, .coral, .seafoam, .blue, .purple]
        return colors[index % colors.count]
    }

    // MARK: - Carte catégorie

    private func categorieCard(label: String, quantite: Double, commandes: Int, total: Double, color: Color) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.gradient)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(color)
                Text("\(store.formatQte(quantite)) · \(commandes) cmd · \(String(format: "%.2f €", total))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            Spacer()
        }
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
