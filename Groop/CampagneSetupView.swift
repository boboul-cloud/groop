//
//  CampagneSetupView.swift
//  Groop
//
//  Configuration de la campagne : titre, unité, variantes avec tailles et couleurs.
//

import SwiftUI

struct CampagneSetupView: View {
    @ObservedObject var store: OrderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Campagne
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.ocean.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.ocean)
                        }
                        TextField("Titre de la campagne", text: $store.titreCampagne)
                            .font(.headline)
                    }

                    Picker("Unité de quantité", selection: $store.uniteQuantite) {
                        Text("Kilogrammes (kg)").tag(UniteQuantite.kg)
                        Text("Unités").tag(UniteQuantite.unite)
                    }

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.ocean.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "phone.fill")
                                .foregroundStyle(.ocean)
                        }
                        TextField("Votre n° de téléphone", text: $store.telephoneVendeur)
                            .keyboardType(.phonePad)
                    }
                } header: {
                    StyledSectionHeader(title: "Campagne", icon: "megaphone.fill")
                } footer: {
                    Text("Votre numéro sera pré-rempli comme destinataire du SMS envoyé par vos clients depuis la page web.")
                }

                // MARK: - Variantes
                Section {
                    ForEach($store.variantes) { $variante in
                        NavigationLink {
                            VarianteDetailView(variante: $variante, unite: store.uniteQuantite)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variante.nom.isEmpty ? "Sans nom" : variante.nom)
                                        .fontWeight(.medium)
                                        .foregroundStyle(variante.nom.isEmpty ? .secondary : .primary)
                                    if variante.prixTailles.isEmpty {
                                        Text(String(format: "%.2f €/%@", variante.prix, store.uniteQuantite.rawValue))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        let minPrixTaille = variante.prixTailles.values.min() ?? 0
                                        let prixAffiche = variante.prix > 0 ? min(variante.prix, minPrixTaille) : minPrixTaille
                                        Text(String(format: "à partir de %.2f €/%@", prixAffiche, store.uniteQuantite.rawValue))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if !variante.tailles.isEmpty {
                                    ModernBadge(text: "\(variante.tailles.count) tailles", color: .oceanLight)
                                }
                                if !variante.couleurs.isEmpty {
                                    ModernBadge(text: "\(variante.couleurs.count) couleurs", color: .seafoam)
                                }
                            }
                        }
                    }
                    .onDelete { indices in
                        store.variantes.remove(atOffsets: indices)
                    }

                    Button {
                        withAnimation {
                            store.variantes.append(Variante())
                        }
                    } label: {
                        Label("Ajouter une variante", systemImage: "plus.circle.fill")
                            .foregroundStyle(.ocean)
                    }
                } header: {
                    StyledSectionHeader(title: "Variantes & Prix", icon: "list.bullet")
                } footer: {
                    Text("Chaque variante peut avoir ses propres tailles et couleurs. Appuyez sur une variante pour la configurer.")
                }

                // MARK: - Catégories clients
                Section {
                    ForEach($store.categories) { $categorie in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.oceanLight)
                            TextField("Nom de la catégorie", text: $categorie.nom)
                        }
                    }
                    .onDelete { indices in
                        let idsToRemove = indices.map { store.categories[$0].id }
                        // Retirer la catégorie des commandes associées
                        for i in store.orders.indices {
                            if let catID = store.orders[i].categorieID, idsToRemove.contains(catID) {
                                store.orders[i].categorieID = nil
                            }
                        }
                        store.categories.remove(atOffsets: indices)
                    }

                    Button {
                        withAnimation {
                            store.categories.append(CategorieClient())
                        }
                    } label: {
                        Label("Ajouter une catégorie", systemImage: "plus.circle.fill")
                            .foregroundStyle(.ocean)
                    }
                } header: {
                    StyledSectionHeader(title: "Catégories clients", icon: "folder")
                } footer: {
                    Text("Optionnel. Permet de regrouper les clients par catégorie pour filtrer les commandes.")
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onDisappear {
                store.save()
            }
        }
    }
}

// MARK: - Détail d'une variante

struct VarianteDetailView: View {
    @Binding var variante: Variante
    let unite: UniteQuantite

    @State private var nouvelleTaille = ""
    @State private var nouvelleCouleur = ""
    @State private var prixText = ""
    @State private var prixTailleTexts: [String: String] = [:]
    @State private var prixCouleurTexts: [String: String] = [:]
    @State private var prixCombiTexts: [String: String] = [:]

    var body: some View {
        Form {
            // MARK: - Infos
            Section {
                TextField("Nom de la variante", text: $variante.nom)
                HStack {
                    Text("Prix")
                    Spacer()
                    TextField("0.00", text: $prixText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: prixText) { _, newValue in
                            let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                            variante.prix = Double(cleaned) ?? 0
                        }
                    Text("€/\(unite.rawValue)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                StyledSectionHeader(title: "Informations", icon: "info.circle")
            }

            // MARK: - Tailles
            Section {
                ForEach(variante.tailles, id: \.self) { taille in
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundStyle(.oceanLight)
                        Text(taille)
                        Spacer()
                        TextField(String(format: "%.2f", variante.prix), text: Binding(
                            get: { prixTailleTexts[taille] ?? "" },
                            set: { newValue in
                                prixTailleTexts[taille] = newValue
                                let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                                if let val = Double(cleaned), val > 0 {
                                    variante.prixTailles[taille] = val
                                } else if newValue.isEmpty {
                                    variante.prixTailles.removeValue(forKey: taille)
                                }
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("€")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indices in
                    let removed = indices.map { variante.tailles[$0] }
                    for t in removed { variante.prixTailles.removeValue(forKey: t) }
                    variante.tailles.remove(atOffsets: indices)
                }

                HStack {
                    TextField("Nouvelle taille…", text: $nouvelleTaille)
                    Button {
                        let trimmed = nouvelleTaille.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        withAnimation {
                            variante.tailles.append(trimmed)
                            nouvelleTaille = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.ocean)
                    }
                    .disabled(nouvelleTaille.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                StyledSectionHeader(title: "Tailles", icon: "ruler")
            } footer: {
                Text("Optionnel. Ajoutez les tailles disponibles. Vous pouvez définir un prix spécifique par taille ; sinon le prix de la variante s'applique.")
            }

            // MARK: - Couleurs
            Section {
                ForEach(variante.couleurs, id: \.self) { couleur in
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.seafoam)
                        Text(couleur)
                        Spacer()
                        TextField(String(format: "%.2f", variante.prix), text: Binding(
                            get: { prixCouleurTexts[couleur] ?? "" },
                            set: { newValue in
                                prixCouleurTexts[couleur] = newValue
                                let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                                if let val = Double(cleaned), val > 0 {
                                    variante.prixCouleurs[couleur] = val
                                } else if newValue.isEmpty {
                                    variante.prixCouleurs.removeValue(forKey: couleur)
                                }
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("€")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indices in
                    let removed = indices.map { variante.couleurs[$0] }
                    for c in removed { variante.prixCouleurs.removeValue(forKey: c) }
                    variante.couleurs.remove(atOffsets: indices)
                }

                HStack {
                    TextField("Nouvelle couleur…", text: $nouvelleCouleur)
                    Button {
                        let trimmed = nouvelleCouleur.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        withAnimation {
                            variante.couleurs.append(trimmed)
                            nouvelleCouleur = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.ocean)
                    }
                    .disabled(nouvelleCouleur.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                StyledSectionHeader(title: "Couleurs", icon: "paintpalette")
            } footer: {
                Text("Optionnel. Ajoutez les couleurs disponibles. Vous pouvez définir un prix spécifique par couleur ; sinon le prix de la variante s'applique.")
            }

            // MARK: - Combinaisons taille × couleur
            if !variante.tailles.isEmpty && !variante.couleurs.isEmpty {
                Section {
                    ForEach(variante.tailles, id: \.self) { taille in
                        ForEach(variante.couleurs, id: \.self) { couleur in
                            let cle = Variante.cleCombinaison(taille, couleur)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(taille)
                                        .font(.subheadline)
                                    Text(couleur)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField(String(format: "%.2f", variante.prix), text: Binding(
                                    get: { prixCombiTexts[cle] ?? "" },
                                    set: { newValue in
                                        prixCombiTexts[cle] = newValue
                                        let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                                        if let val = Double(cleaned), val > 0 {
                                            variante.prixCombinaisons[cle] = val
                                        } else if newValue.isEmpty {
                                            variante.prixCombinaisons.removeValue(forKey: cle)
                                        }
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .padding(6)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text("€")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    StyledSectionHeader(title: "Prix par combinaison", icon: "tablecells")
                } footer: {
                    Text("Définissez un prix pour chaque combinaison taille × couleur. Prioritaire sur les prix par taille ou couleur seuls.")
                }
            }
        }
        .navigationTitle(variante.nom.isEmpty ? "Nouvelle variante" : variante.nom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            prixText = variante.prix > 0 ? String(format: "%.2f", variante.prix) : ""
            for (taille, prix) in variante.prixTailles {
                prixTailleTexts[taille] = String(format: "%.2f", prix)
            }
            for (couleur, prix) in variante.prixCouleurs {
                prixCouleurTexts[couleur] = String(format: "%.2f", prix)
            }
            for (cle, prix) in variante.prixCombinaisons {
                prixCombiTexts[cle] = String(format: "%.2f", prix)
            }
        }
    }
}
