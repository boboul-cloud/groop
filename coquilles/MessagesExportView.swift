//
//  MessagesExportView.swift
//  coquilles
//
//  Messages groupés, export PDF et actions de finalisation.
//

import SwiftUI
import MessageUI
import QuickLook
import UniformTypeIdentifiers

struct MessagesExportView: View {
    @ObservedObject var store: OrderStore

    @State private var messageTexte: String = ""
    @State private var showClientSelection = false
    @State private var clientSelectionType: ClientSelectionType = .commande
    @State private var showCampagneSetup = false
    @State private var showConfirmFinie = false
    @State private var showConfirmReset = false
    @State private var shareItem: IdentifiableURL? = nil
    @State private var previewURL: URL? = nil
    @State private var showExportFeedback = false
    @State private var showSauvegardeNom = false
    @State private var nomSauvegarde = ""
    @State private var showChargerCampagne = false
    @State private var showImportJSON = false
    @State private var showConfirmCharger: String? = nil
    @State private var showSauvegardeFeedback = false
    @State private var showConfirmSupprimer: String? = nil
    @State private var showWebLinkCopied = false

    enum ClientSelectionType {
        case commande, arrivee

        var titre: String {
            switch self {
            case .commande: return "Passer commande"
            case .arrivee: return "Commande arrivée"
            }
        }
    }

    private func clientsForType(_ type: ClientSelectionType) -> [Order] {
        switch type {
        case .commande:
            return store.orders.filter { !$0.telephone.isEmpty }
        case .arrivee:
            return store.orders.filter { !$0.telephone.isEmpty && !$0.lignes.isEmpty }
        }
    }

    private func genererMessageInvitation() -> String {
        var lignes: [String] = []
        let titre = store.titreCampagne.isEmpty ? "notre campagne" : store.titreCampagne
        lignes.append("Bonjour !")
        lignes.append("")
        lignes.append("La campagne « \(titre) » est ouverte !")
        lignes.append("")
        lignes.append("Voici les produits disponibles :")
        for variante in store.variantes where !variante.nom.isEmpty {
            let prix = String(format: "%.2f €/%@", variante.prix, store.uniteQuantite.rawValue)
            lignes.append("")
            lignes.append("▸ \(variante.nom) — \(prix)")
            if !variante.tailles.isEmpty {
                lignes.append("   Tailles : \(variante.tailles.joined(separator: ", "))")
            }
            if !variante.couleurs.isEmpty {
                lignes.append("   Couleurs : \(variante.couleurs.joined(separator: ", "))")
            }
        }
        lignes.append("")
        lignes.append("N'hésitez pas à me contacter pour passer commande !")
        return lignes.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Finalisation
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

                    // MARK: - Export
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

                    // MARK: - Bon de commande groupé
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

                        // Version détaillée : prix + clients
                        BonCommandeButton(
                            icon: "doc.text.magnifyingglass",
                            label: "Détaillé (prix + clients)",
                            style: .outline
                        ) {
                            if let url = store.exporterBonCommande(afficherPrix: true, afficherClients: true) {
                                previewURL = url
                            }
                        }

                        // Version avec prix, sans clients
                        BonCommandeButton(
                            icon: "eurosign.circle",
                            label: "Avec prix, sans clients",
                            style: .outline
                        ) {
                            if let url = store.exporterBonCommande(afficherPrix: true, afficherClients: false) {
                                previewURL = url
                            }
                        }

                        // Version fournisseur : sans clients, sans prix
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

                    // MARK: - Page web commande
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.ocean)
                            Text("Page web commande")
                                .font(.headline)
                                .foregroundStyle(.ocean)
                            Spacer()
                        }

                        Text("Partagez un lien web que vos clients ouvrent dans leur navigateur pour passer commande. La commande vous est envoyée par SMS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let url = store.genererLienWebCommande() {
                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                showWebLinkCopied = true
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copier le lien")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.ocean.opacity(0.1))
                                .foregroundStyle(.ocean)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button {
                                shareItem = IdentifiableURL(url: url)
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Partager le lien")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(LinearGradient.oceanGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Text(url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Ajoutez des variantes dans la configuration pour générer le lien.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // MARK: - Message groupé
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.ocean)
                            Text("Message groupé")
                                .font(.headline)
                                .foregroundStyle(.ocean)
                            Spacer()
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $messageTexte)
                                .frame(minHeight: 100)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            if messageTexte.isEmpty {
                                Text("Saisissez votre message ici…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 16)
                                    .padding(.leading, 12)
                                    .allowsHitTesting(false)
                            }
                        }

                        Button {
                            messageTexte = genererMessageInvitation()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "text.badge.star")
                                Text("Générer une invitation")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ocean.opacity(0.1))
                            .foregroundStyle(.ocean)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(store.variantes.isEmpty)

                        Button {
                            clientSelectionType = .commande
                            showClientSelection = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "megaphone.fill")
                                Text("Passer commande")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(store.tousLesNumeros.count)")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(messageTexte.isEmpty || store.tousLesNumeros.isEmpty || !MessageComposeView.canSendText)
                        .opacity(messageTexte.isEmpty || store.tousLesNumeros.isEmpty ? 0.5 : 1)

                        Button {
                            clientSelectionType = .arrivee
                            showClientSelection = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                Text("Commande arrivée")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(store.numerosAvecCommande.count)")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.seafoam.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(messageTexte.isEmpty || store.numerosAvecCommande.isEmpty || !MessageComposeView.canSendText)
                        .opacity(messageTexte.isEmpty || store.numerosAvecCommande.isEmpty ? 0.5 : 1)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // MARK: - Sauvegarde campagne
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(.ocean)
                            Text("Sauvegarde campagne")
                                .font(.headline)
                                .foregroundStyle(.ocean)
                            Spacer()
                        }

                        Text("Sauvegardez ou restaurez l'intégralité de la campagne (commandes, réglements, variantes…) au format JSON.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Sauvegarder
                        Button {
                            nomSauvegarde = store.titreCampagne
                            showSauvegardeNom = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down.on.square")
                                Text("Sauvegarder la campagne")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LinearGradient.oceanGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Partager le JSON
                        Button {
                            if let url = store.exporterCampagneJSON() {
                                shareItem = IdentifiableURL(url: url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Partager le fichier JSON")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ocean.opacity(0.1))
                            .foregroundStyle(.ocean)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Charger une sauvegarde
                        Button {
                            store.rafraichirListeCampagnes()
                            showChargerCampagne = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.and.arrow.down")
                                Text("Charger une sauvegarde")
                                    .fontWeight(.medium)
                                if !store.campagnesSauvegardees.isEmpty {
                                    Spacer()
                                    Text("\(store.campagnesSauvegardees.count)")
                                        .font(.caption)
                                        .foregroundStyle(.ocean)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.ocean.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Importer un JSON externe
                        Button {
                            showImportJSON = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Importer un fichier JSON")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // MARK: - Réglages
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(.ocean)
                            Text("Réglages")
                                .font(.headline)
                                .foregroundStyle(.ocean)
                            Spacer()
                        }

                        Button {
                            showCampagneSetup = true
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.2")
                                Text("Configurer la campagne")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            showConfirmReset = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Remise à zéro")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.coral.opacity(0.1))
                            .foregroundStyle(.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plus")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showCampagneSetup) {
                CampagneSetupView(store: store)
            }
            .sheet(isPresented: $showClientSelection) {
                ClientSelectionView(
                    store: store,
                    type: clientSelectionType,
                    clients: clientsForType(clientSelectionType),
                    messageTexte: messageTexte
                )
            }
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
            .alert("Remise à zéro", isPresented: $showConfirmReset) {
                Button("Confirmer", role: .destructive) {
                    store.remiseAZero()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Toutes les commandes seront effacées. Les noms et téléphones des clients seront conservés.")
            }
            .alert("Sauvegarder la campagne", isPresented: $showSauvegardeNom) {
                TextField("Nom de la sauvegarde", text: $nomSauvegarde)
                Button("Sauvegarder") {
                    if !nomSauvegarde.trimmingCharacters(in: .whitespaces).isEmpty {
                        _ = store.sauvegarderCampagne(nom: nomSauvegarde.trimmingCharacters(in: .whitespaces))
                        showSauvegardeFeedback = true
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Toute la campagne sera sauvegardée : commandes, réglements, variantes et catégories.")
            }
            .alert("Sauvegarde effectuée ✓", isPresented: $showSauvegardeFeedback) {
                Button("OK") {}
            } message: {
                Text("La campagne « \(nomSauvegarde) » a été sauvegardée.")
            }
            .alert("Lien copié ✓", isPresented: $showWebLinkCopied) {
                Button("OK") {}
            } message: {
                Text("Le lien de commande a été copié dans le presse-papiers.")
            }
            .sheet(isPresented: $showChargerCampagne) {
                CampagneListView(store: store)
            }
            .fileImporter(isPresented: $showImportJSON, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if store.chargerCampagne(depuis: url) {
                        showSauvegardeFeedback = true
                        nomSauvegarde = store.titreCampagne
                    }
                case .failure:
                    break
                }
            }
        }
    }
}

// MARK: - Sélection des clients

struct ClientSelectionView: View {
    @ObservedObject var store: OrderStore
    let type: MessagesExportView.ClientSelectionType
    let clients: [Order]
    let messageTexte: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var showCompose = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if selectedIDs.count == clients.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(clients.map(\.id))
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedIDs.count == clients.count ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.count == clients.count ? .ocean : .secondary)
                            Text(selectedIDs.count == clients.count ? "Tout désélectionner" : "Tout sélectionner")
                                .foregroundStyle(.ocean)
                                .fontWeight(.medium)
                        }
                    }
                }

                Section {
                    ForEach(clients) { client in
                        Button {
                            if selectedIDs.contains(client.id) {
                                selectedIDs.remove(client.id)
                            } else {
                                selectedIDs.insert(client.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(client.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(client.id) ? .seafoam : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.nom.isEmpty ? "Sans nom" : client.nom)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(client.telephone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if !client.lignes.isEmpty {
                                    Text(client.lignes.map { "\(store.formatQte($0.quantite)) \($0.variante)" }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(selectedIDs.count) sur \(clients.count) sélectionné\(selectedIDs.count > 1 ? "s" : "")")
                }
            }
            .navigationTitle(type.titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCompose = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                            Text("Envoyer")
                        }
                        .fontWeight(.semibold)
                    }
                    .disabled(selectedIDs.isEmpty || !MessageComposeView.canSendText)
                }
            }
            .onAppear {
                selectedIDs = Set(clients.map(\.id))
            }
            .sheet(isPresented: $showCompose) {
                let numeros = clients.filter { selectedIDs.contains($0.id) }.map(\.telephone)
                MessageComposeView(recipients: numeros, body: messageTexte)
            }
        }
    }
}

// MARK: - Réglages prix (remplacé par CampagneSetupView)

// MARK: - Liste des campagnes sauvegardées

struct CampagneListView: View {
    @ObservedObject var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCharger: String? = nil
    @State private var confirmSupprimer: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if store.campagnesSauvegardees.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Aucune sauvegarde")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Sauvegardez une campagne pour la retrouver ici.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(store.campagnesSauvegardees, id: \.self) { nom in
                            Button {
                                confirmCharger = nom
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(.ocean)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(nom)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text("Appuyer pour charger")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmSupprimer = nom
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sauvegardes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                store.rafraichirListeCampagnes()
            }
            .alert("Charger cette campagne ?", isPresented: Binding(
                get: { confirmCharger != nil },
                set: { if !$0 { confirmCharger = nil } }
            )) {
                Button("Charger", role: .destructive) {
                    if let nom = confirmCharger {
                        _ = store.chargerCampagne(nom: nom)
                        dismiss()
                    }
                }
                Button("Annuler", role: .cancel) { confirmCharger = nil }
            } message: {
                Text("La campagne actuelle sera remplacée par « \(confirmCharger ?? "") ». Pensez à sauvegarder avant si nécessaire.")
            }
            .alert("Supprimer cette sauvegarde ?", isPresented: Binding(
                get: { confirmSupprimer != nil },
                set: { if !$0 { confirmSupprimer = nil } }
            )) {
                Button("Supprimer", role: .destructive) {
                    if let nom = confirmSupprimer {
                        store.supprimerCampagne(nom: nom)
                    }
                }
                Button("Annuler", role: .cancel) { confirmSupprimer = nil }
            } message: {
                Text("La sauvegarde « \(confirmSupprimer ?? "") » sera définitivement supprimée.")
            }
        }
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
