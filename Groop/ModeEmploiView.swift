//
//  ModeEmploiView.swift
//  Groop
//
//  Mode d'emploi intégré à l'application.
//

import SwiftUI

struct ModeEmploiView: View {
    @State private var expandedSection: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.ocean)
                    Text("Mode d'emploi")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Appuyez sur une section pour en savoir plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                guideSection(
                    id: "demarrage",
                    icon: "play.circle.fill",
                    color: .ocean,
                    titre: "Démarrage rapide",
                    contenu: """
                    1. Au premier lancement, configurez votre campagne : donnez-lui un nom, ajoutez vos produits avec leurs prix, tailles et couleurs.

                    2. Ajoutez vos clients depuis l'onglet Commandes en appuyant sur +.

                    3. Remplissez les commandes de chaque client : variante, taille, couleur et quantité.

                    4. Suivez les paiements et les livraisons en temps réel depuis le Tableau de bord.
                    """
                )

                guideSection(
                    id: "tableau",
                    icon: "chart.bar.fill",
                    color: .seafoam,
                    titre: "Tableau de bord",
                    contenu: """
                    Le Tableau de bord affiche un résumé en temps réel de votre campagne :

                    • Quantité totale commandée
                    • Nombre de participants
                    • Chiffre d'affaires total
                    • Montant déjà encaissé

                    En dessous, le détail par variante de produit (quantité, nombre de commandes, total). En cas de commandes impayées après livraison, une alerte s'affiche.
                    """
                )

                guideSection(
                    id: "commandes",
                    icon: "list.clipboard.fill",
                    color: .ocean,
                    titre: "Commandes",
                    contenu: """
                    L'onglet Commandes liste tous vos clients. Vous pouvez :

                    • Rechercher par nom ou téléphone
                    • Filtrer par statut (commandé, payé, livré) ou catégorie
                    • Ajouter un client avec + (15 max en version gratuite)
                    • Appuyer sur un client pour modifier sa commande
                    • Glisser vers la gauche pour supprimer

                    Pour chaque client, renseignez les lignes de commande (variante, taille, couleur, quantité) et suivez la livraison ligne par ligne.
                    """
                )

                guideSection(
                    id: "paiements",
                    icon: "creditcard.fill",
                    color: .coral,
                    titre: "Paiements",
                    contenu: """
                    L'onglet Paiements affiche la progression des encaissements :

                    • Barre de progression vers 100 %
                    • Détail par mode : chèques et espèces
                    • Commandes payées vs impayées
                    • Alerte pour les commandes livrées mais non payées

                    Pour enregistrer un paiement, ouvrez la fiche d'un client dans Commandes, puis ajoutez un paiement (montant, mode, date). Vous pouvez enregistrer plusieurs paiements partiels.
                    """
                )

                guideSection(
                    id: "messages",
                    icon: "message.fill",
                    color: .oceanLight,
                    titre: "Messages & Page web",
                    contenu: """
                    Depuis l'onglet Plus > Commande :

                    • Page web : générez un lien que vos clients ouvrent sur leur téléphone pour commander en ligne. La commande vous est envoyée par SMS.
                    • SMS d'invitation : envoyez un SMS groupé avec le récapitulatif des produits et prix.
                    • SMS « Commande arrivée » : prévenez vos clients que leur commande est prête.
                    • Choisissez les destinataires un par un ou sélectionnez tout le monde.
                    """
                )

                guideSection(
                    id: "exports",
                    icon: "doc.richtext",
                    color: .seafoam,
                    titre: "Exports PDF (Pro)",
                    contenu: """
                    Depuis Plus > Exportation, générez des documents PDF :

                    • Récapitulatif : détail complet par client avec statuts de paiement et livraison.
                    • Bon de commande : par variante de produit, en 3 versions (détaillé, sans noms, fournisseur).
                    • Fiche de distribution : organisée par catégorie avec cases à cocher.

                    Vous pouvez aussi exporter la liste de vos clients en fichier texte (.csv) depuis les Réglages.

                    ⭐ Fonctionnalité réservée à Groop Pro.
                    """
                )

                guideSection(
                    id: "campagne",
                    icon: "externaldrive.fill",
                    color: .ocean,
                    titre: "Campagnes (Pro)",
                    contenu: """
                    Depuis Plus > Campagne :

                    • Sauvegarder la campagne en cours (produits, clients, commandes) dans un fichier JSON.
                    • Charger une campagne sauvegardée précédemment.
                    • Partager une campagne avec un autre appareil.
                    • Nouvelle campagne : choix de conserver ou effacer les clients existants.

                    ⭐ Fonctionnalité réservée à Groop Pro.
                    """
                )

                guideSection(
                    id: "reglages",
                    icon: "gearshape.fill",
                    color: .secondary,
                    titre: "Réglages",
                    contenu: """
                    • Remise à zéro : efface toutes les commandes (les noms et téléphones sont conservés).
                    • Importer une liste de clients depuis un fichier texte ou CSV (Pro).
                    • Exporter la liste de clients vers un fichier (Pro).
                    """
                )

                guideSection(
                    id: "ia",
                    icon: "cpu.fill",
                    color: .purple,
                    titre: "Import IA (PDF)",
                    contenu: """
                    L'import par intelligence artificielle permet de créer automatiquement vos produits à partir d'un fichier PDF de tarifs fournisseur.

                    Pour l'utiliser :
                    1. Allez dans Réglages > Clé API OpenAI et collez votre clé.
                    2. Lors de la configuration d'une campagne, appuyez sur « Importer un fichier » et sélectionnez un PDF.
                    3. L'IA analyse chaque page du PDF et extrait automatiquement les noms, tailles, contenants et prix.

                    Formats supportés :
                    • PDF avec texte intégré (catalogues, tarifs fournisseurs)
                    • Fichiers CSV ou texte tabulé
                    • PDF scannés (via OCR automatique en dernier recours)

                    L'import crée les variantes avec leurs prix par taille et contenant. Vous pouvez ensuite ajuster manuellement si nécessaire.

                    💡 Astuce : un PDF bien structuré (avec colonnes claires) donnera de meilleurs résultats.

                    ⚠️ Nécessite une clé API OpenAI (payante à l'usage, quelques centimes par import).
                    """
                )

                guideSection(
                    id: "pro",
                    icon: "star.circle.fill",
                    color: .orange,
                    titre: "Groop Pro",
                    contenu: """
                    La version gratuite inclut : 1 campagne, 15 clients max, commandes, paiements, page web et SMS.

                    Groop Pro débloque :
                    • Clients illimités
                    • Sauvegarde et restauration de campagnes
                    • Exports PDF (récapitulatif, bon de commande, fiche de distribution)
                    • Import et export de listes de clients

                    Achat unique depuis Plus > Groop Pro.
                    """
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mode d'emploi")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section dépliable

    private func guideSection(id: String, icon: String, color: Color, titre: String, contenu: String) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedSection = expandedSection == id ? nil : id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 28)
                    Text(titre)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expandedSection == id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if expandedSection == id {
                Divider().padding(.leading, 52)
                Text(contenu)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
