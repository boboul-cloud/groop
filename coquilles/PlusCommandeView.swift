//
//  PlusCommandeView.swift
//  coquilles
//
//  Page web de commande et messages groupés SMS.
//

import SwiftUI
import MessageUI

struct PlusCommandeView: View {
    @ObservedObject var store: OrderStore

    @State private var messageTexte: String = ""
    @State private var clientSelectionItem: ClientSelectionItem? = nil
    @State private var shareItem: IdentifiableURL? = nil
    @State private var showWebLinkCopied = false

    struct ClientSelectionItem: Identifiable {
        let id = UUID()
        let type: ClientSelectionType
        let message: String
    }

    enum ClientSelectionType {
        case commande, arrivee, pageWeb

        var titre: String {
            switch self {
            case .commande: return "Passer commande"
            case .arrivee: return "Commande arrivée"
            case .pageWeb: return "Envoyer le lien"
            }
        }
    }

    private func clientsForType(_ type: ClientSelectionType) -> [Order] {
        switch type {
        case .commande, .pageWeb:
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
        ScrollView {
            VStack(spacing: 20) {
                pageWebSection
                messageGroupeSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Commande")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(item: $clientSelectionItem) { item in
            ClientSelectionView(
                store: store,
                type: item.type,
                clients: clientsForType(item.type),
                messageTexte: item.message
            )
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("Lien copié ✓", isPresented: $showWebLinkCopied) {
            Button("OK") {}
        } message: {
            Text("Le lien de commande a été copié dans le presse-papiers.")
        }
    }

    // MARK: - Page web

    @ViewBuilder
    private var pageWebSection: some View {
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

                Button {
                    clientSelectionItem = ClientSelectionItem(type: .pageWeb, message: url.absoluteString)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                        Text("Envoyer par SMS")
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
                    .background(Color.ocean.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(store.tousLesNumeros.isEmpty || !MessageComposeView.canSendText)
            } else {
                Text("Ajoutez des variantes dans la configuration pour générer le lien.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Message groupé

    private var messageGroupeSection: some View {
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
                clientSelectionItem = ClientSelectionItem(type: .commande, message: messageTexte)
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
                clientSelectionItem = ClientSelectionItem(type: .arrivee, message: messageTexte)
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
    }
}

// MARK: - Sélection des clients

struct ClientSelectionView: View {
    @ObservedObject var store: OrderStore
    let type: PlusCommandeView.ClientSelectionType
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
