//
//  CommandesView.swift
//  Groop
//
//  Liste des commandes modernisée avec recherche et filtres.
//

import SwiftUI

struct CommandesView: View {
    @ObservedObject var store: OrderStore
    @ObservedObject var storeManager: StoreManager
    @State private var searchText = ""
    @State private var filtreCommande: Bool? = nil
    @State private var filtrePaye: Bool? = nil
    @State private var filtreLivre: Bool? = nil
    @State private var filtreCategorie: UUID? = nil
    @State private var showProUpgrade = false
    @State private var triCommandes: TriCommandes = .ajout

    enum TriCommandes: String, CaseIterable {
        case ajout = "Ordre d'ajout"
        case nom = "Nom"
        case montant = "Montant"
        case statut = "Statut (impayés d'abord)"
    }

    private func filtrerCommande(_ order: Order) -> Bool {
        let matchSearch = searchText.isEmpty
            || order.nomComplet.localizedCaseInsensitiveContains(searchText)
            || order.telephone.contains(searchText)

        let matchCommande: Bool
        switch filtreCommande {
        case .none: matchCommande = true
        case .some(true): matchCommande = order.estValide
        case .some(false): matchCommande = !order.estValide
        }

        let matchPaye: Bool
        switch filtrePaye {
        case .none: matchPaye = true
        case .some(true): matchPaye = order.estEntierementRegle(variantes: store.variantes)
        case .some(false): matchPaye = !order.estEntierementRegle(variantes: store.variantes)
        }

        let matchLivre: Bool
        switch filtreLivre {
        case .none: matchLivre = true
        case .some(true): matchLivre = order.estLivre
        case .some(false): matchLivre = !order.estLivre
        }

        let matchCategorie: Bool
        if let catID = filtreCategorie {
            matchCategorie = order.categorieID == catID
        } else {
            matchCategorie = true
        }

        return matchSearch && matchCommande && matchPaye && matchLivre && matchCategorie
    }

    var commandesFiltrees: [Binding<Order>] {
        let filtered = $store.orders.filter { filtrerCommande($0.wrappedValue) }
        switch triCommandes {
        case .ajout:
            return filtered
        case .nom:
            return filtered.sorted { $0.wrappedValue.nomComplet.localizedCompare($1.wrappedValue.nomComplet) == .orderedAscending }
        case .montant:
            return filtered.sorted { ($1.wrappedValue.total(variantes: store.variantes) ?? 0) < ($0.wrappedValue.total(variantes: store.variantes) ?? 0) }
        case .statut:
            return filtered.sorted { a, b in
                let aImpaye = a.wrappedValue.resteARegler(variantes: store.variantes) > 0 && (a.wrappedValue.estLivre || a.wrappedValue.partiellementLivre)
                let bImpaye = b.wrappedValue.resteARegler(variantes: store.variantes) > 0 && (b.wrappedValue.estLivre || b.wrappedValue.partiellementLivre)
                if aImpaye != bImpaye { return aImpaye }
                let aNonLivre = a.wrappedValue.estValide && !a.wrappedValue.estLivre
                let bNonLivre = b.wrappedValue.estValide && !b.wrappedValue.estLivre
                if aNonLivre != bNonLivre { return aNonLivre }
                return a.wrappedValue.nomComplet.localizedCompare(b.wrappedValue.nomComplet) == .orderedAscending
            }
        }
    }

    /// Sections groupées par catégorie : [(titre, commandes)]
    var sectionsParCategorie: [(id: String, titre: String, commandes: [Binding<Order>])] {
        let filtrees = commandesFiltrees
        guard !store.categories.isEmpty else {
            return [("all", "Toutes", filtrees)]
        }

        var sections: [(id: String, titre: String, commandes: [Binding<Order>])] = []
        for cat in store.categories {
            let ordersInCat = filtrees.filter { $0.wrappedValue.categorieID == cat.id }
            if !ordersInCat.isEmpty {
                sections.append((cat.id.uuidString, cat.nom.isEmpty ? "Sans nom" : cat.nom, ordersInCat))
            }
        }
        let sansCategorie = filtrees.filter { binding in
            let catID = binding.wrappedValue.categorieID
            return catID == nil || !store.categories.contains(where: { $0.id == catID })
        }
        if !sansCategorie.isEmpty {
            sections.append(("none", "Sans catégorie", sansCategorie))
        }
        return sections
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Filtres en cascade
                Section {
                    VStack(spacing: 6) {
                        CascadeFilterRow(label: "Commandé", selection: $filtreCommande)
                        CascadeFilterRow(label: "Payé", selection: $filtrePaye)
                        CascadeFilterRow(label: "Livré", selection: $filtreLivre)

                        if !store.categories.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Text("Catégorie")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    ForEach(store.categories) { cat in
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                filtreCategorie = filtreCategorie == cat.id ? nil : cat.id
                                            }
                                        } label: {
                                            Text(cat.nom.isEmpty ? "Sans nom" : cat.nom)
                                                .font(.subheadline)
                                                .fontWeight(filtreCategorie == cat.id ? .semibold : .regular)
                                                .foregroundStyle(filtreCategorie == cat.id ? .white : .ocean)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(filtreCategorie == cat.id ? Color.oceanLight : Color.ocean.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                // MARK: - Liste
                ForEach(sectionsParCategorie, id: \.id) { section in
                    Section {
                        ForEach(section.commandes) { $order in
                            NavigationLink(value: order.id) {
                                ModernOrderRow(order: order, store: store)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                if let index = store.orders.firstIndex(where: { $0.id == order.id }) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            store.orders.remove(at: index)
                                            store.save()
                                        }
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        if store.categories.isEmpty {
                            EmptyView()
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.caption)
                                    .foregroundStyle(.oceanLight)
                                Text(section.titre)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.ocean)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $searchText, prompt: "Rechercher un client…")
            .navigationDestination(for: UUID.self) { orderID in
                if let index = store.orders.firstIndex(where: { $0.id == orderID }) {
                    ModernOrderDetailView(order: $store.orders[index], store: store)
                }
            }
            .navigationTitle("Commandes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Tri", selection: $triCommandes) {
                            ForEach(TriCommandes.allCases, id: \.self) { tri in
                                Text(tri.rawValue).tag(tri)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .foregroundStyle(.ocean)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if storeManager.clientsLimiteAtteinte(count: store.orders.count) {
                            showProUpgrade = true
                        } else {
                            withAnimation(.spring(response: 0.4)) {
                                store.ajouterCommande(categorieID: filtreCategorie)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.ocean)
                            .symbolEffect(.bounce, value: store.orders.count)
                    }
                }
            }
            .sheet(isPresented: $showProUpgrade) {
                GroopProView(storeManager: storeManager)
            }
        }
    }
}

// MARK: - Filtre en cascade

struct CascadeFilterRow: View {
    let label: String
    @Binding var selection: Bool?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            ForEach([true, false], id: \.self) { value in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selection = selection == value ? nil : value
                    }
                } label: {
                    Text(value ? "Oui" : "Non")
                        .font(.subheadline)
                        .fontWeight(selection == value ? .semibold : .regular)
                        .foregroundStyle(selection == value ? .white : .ocean)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selection == value ? (value ? Color.seafoam : Color.coral) : Color.ocean.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

// MARK: - Ligne de commande modernisée

struct ModernOrderRow: View {
    let order: Order
    let store: OrderStore

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(avatarColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Nom + Total
                HStack {
                    Text(order.nomComplet.isEmpty ? "Sans nom" : order.nomComplet)
                        .fontWeight(.semibold)
                        .foregroundStyle(order.nomComplet.isEmpty ? .secondary : .primary)

                    Spacer()

                    if let total = order.total(variantes: store.variantes) {
                        Text(String(format: "%.2f €", total))
                            .fontWeight(.bold)
                            .foregroundStyle(.ocean)
                    }
                }

                // Détail variantes empilées
                ForEach(order.lignes) { ligne in
                    if !ligne.variante.isEmpty {
                        HStack(spacing: 4) {
                            Text(ligne.variante)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.ocean)

                            if let taille = ligne.taille, !taille.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(taille)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let couleur = ligne.couleur, !couleur.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(couleur)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(store.formatQte(ligne.quantite))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            if let lineTotal = ligne.total(variantes: store.variantes) {
                                Text(String(format: "%.2f €", lineTotal))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.ocean.opacity(0.7))
                            }
                        }
                    }
                }

                // Badges statut
                HStack(spacing: 6) {
                    let reste = order.resteARegler(variantes: store.variantes)
                    if reste > 0 && (order.estLivre || order.partiellementLivre) {
                        ModernBadge(
                            text: String(format: "Dû: %.2f €", reste),
                            color: .coral,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                    if order.estLivre {
                        ModernBadge(text: "Livré", color: .green, icon: "shippingbox.fill")
                    } else if order.partiellementLivre {
                        let pct = order.quantiteTotale > 0 ? Int(order.quantiteTotaleLivree / order.quantiteTotale * 100) : 0
                        ModernBadge(text: "Livré \(pct)%", color: .orange, icon: "shippingbox.fill")
                    }
                    if order.estEntierementRegle(variantes: store.variantes) {
                        ModernBadge(text: "Payé", color: order.estLivre ? .green : .blue, icon: "checkmark.circle.fill")
                    } else if order.totalRegle > 0 {
                        ModernBadge(text: String(format: "Payé %.2f €", order.totalRegle), color: .blue, icon: "checkmark.circle.fill")
                    } else if order.estValide && !order.estLivre {
                        ModernBadge(text: "Non livré", color: .orange, icon: "clock.fill")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let p = order.prenom.first.map { String($0).uppercased() } ?? ""
        let n = order.nom.first.map { String($0).uppercased() } ?? ""
        let result = p + n
        return result.isEmpty ? "?" : result
    }

    private var avatarColor: Color {
        if order.estLivre && order.estEntierementRegle(variantes: store.variantes) { return .green }
        let reste = order.resteARegler(variantes: store.variantes)
        if reste > 0 && (order.estLivre || order.partiellementLivre) { return .coral }
        if order.estRegle { return .blue }
        if order.estValide { return .orange }
        return .gray
    }
}

// MARK: - Détail commande modernisé

struct ModernOrderDetailView: View {
    @Binding var order: Order
    @ObservedObject var store: OrderStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAlertNonRegle = false
    @State private var showAjoutReglement = false
    @State private var montantReglement: String = ""
    @State private var modeReglement: ModePaiement = .especes
    @State private var showLivraisonPartielle = false
    @State private var qtesALivrer: [UUID: Double] = [:]
    @State private var showAlertAnnulerLivraison = false
    @State private var showAlertAnnulerReglements = false

    var body: some View {
        Form {
            // MARK: - Informations
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.ocean.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "person.fill")
                            .foregroundStyle(.ocean)
                    }
                    TextField("Prénom", text: $order.prenom)
                        .font(.headline)
                }
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.ocean.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "person.text.rectangle")
                            .foregroundStyle(.ocean)
                    }
                    TextField("Nom", text: $order.nom)
                        .font(.headline)
                }
                if !store.categories.isEmpty {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.oceanLight.opacity(0.15))
                                .frame(width: 50, height: 50)
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.oceanLight)
                        }
                        Picker("Catégorie", selection: $order.categorieID) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(store.categories) { cat in
                                Text(cat.nom.isEmpty ? "Sans nom" : cat.nom).tag(UUID?.some(cat.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.seafoam.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.seafoam)
                    }
                    TextField("Téléphone", text: $order.telephone)
                        .keyboardType(.phonePad)
                    if !order.telephone.isEmpty,
                       let url = URL(string: "tel:\(order.telephone.filter { $0.isNumber || $0 == "+" })") {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Image(systemName: "phone.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                StyledSectionHeader(title: "Informations", icon: "person.text.rectangle")
            }

            // MARK: - Alerte doublon
            if let doublon = store.doublonPour(order) {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Doublon possible")
                                .font(.subheadline.bold())
                            Text("Client similaire : \(doublon.nomComplet.isEmpty ? doublon.telephone : doublon.nomComplet)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - Statut livraison
            if order.estLivre || order.partiellementLivre {
                Section {
                    if order.estLivre {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.seafoam)
                                .font(.title3)
                                .symbolEffect(.pulse)
                            Text("LIVRÉ")
                                .foregroundStyle(.seafoam)
                                .fontWeight(.bold)
                            if let date = order.dateLivraison {
                                Spacer()
                                Text(formatDate(date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            Text("PARTIELLEMENT LIVRÉ")
                                .foregroundStyle(.orange)
                                .fontWeight(.bold)
                            Spacer()
                            let pct = order.quantiteTotale > 0 ? Int(order.quantiteTotaleLivree / order.quantiteTotale * 100) : 0
                            Text("\(pct)%")
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 4)
                    }

                    // Détail livraison par ligne
                    ForEach(order.lignes) { ligne in
                        if !ligne.variante.isEmpty {
                            HStack {
                                Text(ligne.variante)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(store.formatQte(ligne.quantiteLivree)) / \(store.formatQte(ligne.quantite))")
                                    .font(.caption)
                                    .foregroundStyle(ligne.estLivree ? .seafoam : .orange)
                                    .fontWeight(.medium)
                                Image(systemName: ligne.estLivree ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ligne.estLivree ? .seafoam : .orange)
                            }
                        }
                    }

                    Button {
                        showAlertAnnulerLivraison = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text("Annuler la livraison")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .tint(.coral)
                } header: {
                    StyledSectionHeader(title: "Livraison", icon: "shippingbox.fill")
                }
            }

            // MARK: - Lignes de commande
            Section {
                ForEach($order.lignes) { $ligne in
                    LigneCommandeRow(ligne: $ligne, store: store, disabled: order.estLivre)
                }
                .onDelete { indices in
                    guard !order.estLivre else { return }
                    order.lignes.remove(atOffsets: indices)
                }

                if !order.estLivre {
                    Button {
                        withAnimation {
                            order.lignes.append(LigneCommande())
                        }
                    } label: {
                        Label("Ajouter une variante", systemImage: "plus.circle.fill")
                            .foregroundStyle(.ocean)
                    }
                }
            } header: {
                StyledSectionHeader(title: "Commande", icon: "cart.fill")
            }

            // MARK: - Prix
            if order.estValide {
                Section {
                    ForEach(order.lignes) { ligne in
                        if let total = ligne.total(variantes: store.variantes) {
                            ModernSummaryRow(
                                label: "\(store.formatQte(ligne.quantite)) \(ligne.variante)",
                                value: String(format: "%.2f €", total)
                            )
                        }
                    }
                    if let total = order.total(variantes: store.variantes) {
                        ModernSummaryRow(
                            label: "Total",
                            value: String(format: "%.2f €", total),
                            valueColor: .ocean,
                            bold: true
                        )
                    }
                } header: {
                    StyledSectionHeader(title: "Prix", icon: "eurosign.circle")
                }
            }

            // MARK: - Paiements
            if order.estValide {
                Section {
                    // Liste des règlements existants
                    ForEach(order.reglements) { reglement in
                        HStack {
                            Image(systemName: reglement.modePaiement == .cheque ? "doc.plaintext.fill" : "banknote.fill")
                                .foregroundStyle(.seafoam)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reglement.modePaiement.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(formatDate(reglement.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.2f €", reglement.montant))
                                .fontWeight(.semibold)
                                .foregroundStyle(.seafoam)
                        }
                    }
                    .onDelete { indices in
                        let ids = indices.map { order.reglements[$0].id }
                        for id in ids {
                            order.supprimerReglement(id)
                        }
                        store.save()
                    }

                    // Résumé
                    if order.totalRegle > 0 {
                        ModernSummaryRow(
                            label: "Total réglé",
                            value: String(format: "%.2f €", order.totalRegle),
                            valueColor: .seafoam,
                            bold: true
                        )
                    }

                    let reste = order.resteARegler(variantes: store.variantes)
                    if reste > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.coral)
                            Text("Reste à régler")
                                .foregroundStyle(.coral)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(String(format: "%.2f €", reste))
                                .foregroundStyle(.coral)
                                .fontWeight(.bold)
                        }

                        // Boutons règlement rapide
                        Button {
                            withAnimation {
                                order.ajouterReglement(montant: reste, mode: .especes)
                                store.save()
                            }
                        } label: {
                            Label("Tout régler en espèces", systemImage: "banknote.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.ocean)

                        Button {
                            withAnimation {
                                order.ajouterReglement(montant: reste, mode: .cheque)
                                store.save()
                            }
                        } label: {
                            Label("Tout régler par chèque", systemImage: "doc.plaintext.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.ocean)

                        // Règlement partiel
                        Button {
                            montantReglement = ""
                            modeReglement = .especes
                            showAjoutReglement = true
                        } label: {
                            Label("Règlement partiel…", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.oceanLight)
                    } else if order.estEntierementRegle(variantes: store.variantes) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.seafoam)
                                .symbolEffect(.pulse)
                            Text("Entièrement réglé")
                                .foregroundStyle(.seafoam)
                                .fontWeight(.bold)
                        }
                    }

                    if !order.reglements.isEmpty {
                        Button {
                            showAlertAnnulerReglements = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                Text("Annuler les règlements")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .tint(.coral)
                    }
                } header: {
                    StyledSectionHeader(title: "Paiements", icon: "creditcard")
                }
            }

            // MARK: - Livraison
            if order.estValide && !order.estLivre {
                Section {
                    // Livrer tout
                    Button {
                        if order.estEntierementRegle(variantes: store.variantes) {
                            withAnimation(.spring(response: 0.5)) {
                                order.livrerTout()
                                store.save()
                            }
                        } else {
                            showAlertNonRegle = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox.and.arrow.backward.fill")
                            Text("Livrer tout")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .tint(.seafoam)

                    // Livraison partielle
                    Button {
                        qtesALivrer = [:]
                        for ligne in order.lignes where ligne.resteALivrer > 0 {
                            qtesALivrer[ligne.id] = ligne.resteALivrer
                        }
                        showLivraisonPartielle = true
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                            Text("Livraison partielle…")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .tint(.oceanLight)
                } header: {
                    StyledSectionHeader(title: "Livraison", icon: "shippingbox")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(order.nomComplet.isEmpty ? "Nouvelle commande" : order.nomComplet)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(isPresented: $showAjoutReglement) {
            ReglementPartielSheet(
                montantTexte: $montantReglement,
                mode: $modeReglement,
                maxMontant: order.resteARegler(variantes: store.variantes)
            ) { montant, mode in
                withAnimation {
                    order.ajouterReglement(montant: montant, mode: mode)
                    store.save()
                }
            }
        }
        .sheet(isPresented: $showLivraisonPartielle) {
            LivraisonPartielleSheet(
                lignes: order.lignes,
                store: store,
                qtesALivrer: $qtesALivrer
            ) {
                withAnimation(.spring(response: 0.5)) {
                    for (ligneID, qte) in qtesALivrer {
                        order.livrerLigne(ligneID, quantite: qte)
                    }
                    store.save()
                }
            }
        }
        .alert("Annuler la livraison ?", isPresented: $showAlertAnnulerLivraison) {
            Button("Annuler la livraison", role: .destructive) {
                withAnimation(.spring(response: 0.5)) {
                    order.annulerLivraison()
                    store.save()
                }
            }
            Button("Non", role: .cancel) {}
        } message: {
            Text("La livraison de \(order.nomComplet.isEmpty ? "cette commande" : order.nomComplet) sera annulée.")
        }
        .alert("Annuler les règlements ?", isPresented: $showAlertAnnulerReglements) {
            Button("Annuler les règlements", role: .destructive) {
                withAnimation(.spring(response: 0.5)) {
                    order.annulerReglements()
                    store.save()
                }
            }
            Button("Non", role: .cancel) {}
        } message: {
            Text("Tous les règlements de \(order.nomComplet.isEmpty ? "cette commande" : order.nomComplet) seront supprimés.")
        }
        .alert("Commande non entièrement réglée", isPresented: $showAlertNonRegle) {
            Button("Livrer quand même", role: .destructive) {
                withAnimation(.spring(response: 0.5)) {
                    order.livrerTout()
                    store.save()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(order.nom) n'a pas encore entièrement réglé sa commande. Voulez-vous livrer quand même ?")
        }
        .onDisappear {
            store.save()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale(identifier: "fr_FR")
        return df.string(from: date)
    }
}

// MARK: - Ligne de commande individuelle

struct LigneCommandeRow: View {
    @Binding var ligne: LigneCommande
    @ObservedObject var store: OrderStore
    let disabled: Bool

    @State private var repeatTimer: Timer?

    private func startRepeat(increment: Double) {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            let newValue = ligne.quantite + increment
            if newValue >= 0 {
                ligne.quantite = newValue
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Variante", selection: $ligne.variante) {
                Text("—").tag("")
                ForEach(store.variantes) { v in
                    Text(v.nom).tag(v.nom)
                }
            }
            .id("variante-\(ligne.id)-\(store.variantes.map(\.nom).joined())")
            .disabled(disabled)

            if let selectedVariante = store.variantes.first(where: { $0.nom == ligne.variante }) {
                let aDesCombinaisons = !selectedVariante.prixCombinaisons.isEmpty

                if !selectedVariante.tailles.isEmpty {
                    // Filtrer les tailles : si combinaisons et couleur choisie, ne montrer que les tailles valides
                    let taillesFiltrees: [String] = {
                        guard aDesCombinaisons, let c = ligne.couleur else { return selectedVariante.tailles }
                        let valides = selectedVariante.tailles.filter { t in
                            selectedVariante.prixCombinaisons[Variante.cleCombinaison(t, c)] != nil
                        }
                        return valides.isEmpty ? selectedVariante.tailles : valides
                    }()

                    Picker("Taille", selection: $ligne.taille) {
                        Text("—").tag(Optional<String>.none)
                        ForEach(taillesFiltrees, id: \.self) { t in
                            Text(t).tag(Optional(t))
                        }
                    }
                    .id("taille-\(ligne.id)-\(ligne.couleur ?? "")")
                    .disabled(disabled)
                }

                if !selectedVariante.couleurs.isEmpty {
                    // Filtrer les couleurs : si combinaisons et taille choisie, ne montrer que les couleurs valides
                    let couleursFiltrees: [String] = {
                        guard aDesCombinaisons, let t = ligne.taille else { return selectedVariante.couleurs }
                        let valides = selectedVariante.couleurs.filter { c in
                            selectedVariante.prixCombinaisons[Variante.cleCombinaison(t, c)] != nil
                        }
                        return valides.isEmpty ? selectedVariante.couleurs : valides
                    }()

                    Picker("Couleur", selection: $ligne.couleur) {
                        Text("—").tag(Optional<String>.none)
                        ForEach(couleursFiltrees, id: \.self) { c in
                            Text(c).tag(Optional(c))
                        }
                    }
                    .id("couleur-\(ligne.id)-\(ligne.taille ?? "")")
                    .disabled(disabled)
                }
            }

            // Quantité
            HStack(spacing: 16) {
                Text("Quantité")
                    .foregroundStyle(.secondary)
                Spacer()

                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.coral)
                    .onTapGesture {
                        if ligne.quantite >= store.incrementQuantite {
                            withAnimation { ligne.quantite -= store.incrementQuantite }
                        }
                    }
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                        if pressing { startRepeat(increment: -store.incrementQuantite) } else { stopRepeat() }
                    }, perform: {})
                    .opacity(disabled ? 0.3 : 1)
                    .allowsHitTesting(!disabled)

                Text(store.formatQte(ligne.quantite))
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.ocean)
                    .contentTransition(.numericText())
                    .frame(minWidth: 60)
                    .multilineTextAlignment(.center)

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.seafoam)
                    .onTapGesture {
                        withAnimation { ligne.quantite += store.incrementQuantite }
                    }
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                        if pressing { startRepeat(increment: store.incrementQuantite) } else { stopRepeat() }
                    }, perform: {})
                    .opacity(disabled ? 0.3 : 1)
                    .allowsHitTesting(!disabled)
            }

            if let total = ligne.total(variantes: store.variantes), total > 0 {
                HStack {
                    Spacer()
                    Text(String(format: "%.2f €", total))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.ocean)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Règlement partiel (sheet)

struct ReglementPartielSheet: View {
    @Binding var montantTexte: String
    @Binding var mode: ModePaiement
    let maxMontant: Double
    let onConfirm: (Double, ModePaiement) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Reste à régler")
                        Spacer()
                        Text(String(format: "%.2f €", maxMontant))
                            .fontWeight(.bold)
                            .foregroundStyle(.coral)
                    }
                }

                Section {
                    TextField("Montant", text: $montantTexte)
                        .keyboardType(.decimalPad)
                    Picker("Mode", selection: $mode) {
                        ForEach(ModePaiement.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                } header: {
                    Text("Règlement")
                }
            }
            .navigationTitle("Règlement partiel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        let cleaned = montantTexte.replacingOccurrences(of: ",", with: ".")
                        guard let montant = Double(cleaned), montant > 0 else { return }
                        let finalMontant = min(montant, maxMontant)
                        onConfirm(finalMontant, mode)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Livraison partielle (sheet)

struct LivraisonPartielleSheet: View {
    let lignes: [LigneCommande]
    let store: OrderStore
    @Binding var qtesALivrer: [UUID: Double]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(lignes.filter { $0.resteALivrer > 0 }) { ligne in
                    Section {
                        VStack(spacing: 8) {
                            HStack {
                                HStack(spacing: 4) {
                                    Text(ligne.variante)
                                        .fontWeight(.semibold)
                                    if let taille = ligne.taille, !taille.isEmpty {
                                        Text("· \(taille)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("Reste : \(store.formatQte(ligne.resteALivrer))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if ligne.quantiteLivree > 0 {
                                HStack {
                                    Text("Déjà livré")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(store.formatQte(ligne.quantiteLivree))
                                        .font(.caption)
                                        .foregroundStyle(.seafoam)
                                }
                            }

                            HStack(spacing: 16) {
                                Text("À livrer")
                                    .foregroundStyle(.secondary)
                                Spacer()

                                let currentQte = qtesALivrer[ligne.id] ?? 0

                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.coral)
                                    .onTapGesture {
                                        if currentQte >= store.incrementQuantite {
                                            qtesALivrer[ligne.id] = currentQte - store.incrementQuantite
                                        }
                                    }

                                Text(store.formatQte(currentQte))
                                    .font(.callout)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.ocean)
                                    .contentTransition(.numericText())
                                    .frame(minWidth: 60)
                                    .multilineTextAlignment(.center)

                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.seafoam)
                                    .onTapGesture {
                                        let max = ligne.resteALivrer
                                        if currentQte + store.incrementQuantite <= max {
                                            qtesALivrer[ligne.id] = currentQte + store.incrementQuantite
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Livraison partielle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Livrer") {
                        onConfirm()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(qtesALivrer.values.allSatisfy { $0 == 0 })
                }
            }
        }
        .presentationDetents([.large])
    }
}
