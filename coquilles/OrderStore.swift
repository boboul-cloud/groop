//
//  OrderStore.swift
//  coquilles
//
//  Created by Robert Oulhen on 11/03/2026.
//

import Foundation
import Combine
import SwiftUI
import UIKit

/// Snapshot complet d'une campagne, exportable en JSON.
struct CampagneData: Codable {
    var titreCampagne: String
    var uniteQuantite: UniteQuantite
    var variantes: [Variante]
    var categories: [CategorieClient]
    var orders: [Order]
    var telephoneVendeur: String?
}

class OrderStore: ObservableObject {
    @Published var orders: [Order] = []
    @Published var titreCampagne: String = "Coquilles"
    @Published var uniteQuantite: UniteQuantite = .kg
    @Published var variantes: [Variante] = []
    @Published var categories: [CategorieClient] = []
    @Published var campagnesSauvegardees: [String] = []
    @Published var telephoneVendeur: String = ""

    private let ordersKey = "savedOrders"
    private let titreKey = "campagneTitre"
    private let uniteKey = "campagneUnite"
    private let variantesKey = "campagneVariantes"
    private let categoriesKey = "campagneCategories"
    private let telVendeurKey = "campagneTelVendeur"

    init() {
        load()
    }

    // MARK: - Helpers

    var labelUnite: String { uniteQuantite.rawValue }

    var incrementQuantite: Double { uniteQuantite == .kg ? 0.5 : 1 }

    var formatQuantite: String { uniteQuantite == .kg ? "%.1f" : "%.0f" }

    func formatQte(_ value: Double) -> String {
        String(format: formatQuantite, value) + " " + labelUnite
    }

    // MARK: - Computed Properties

    var totalQuantite: Double {
        orders.flatMap(\.lignes).map(\.quantite).reduce(0, +)
    }

    var totalGeneral: Double {
        orders.filter(\.estValide).compactMap {
            $0.total(variantes: variantes)
        }.reduce(0, +)
    }

    var totalPaye: Double {
        orders.filter(\.estValide).compactMap {
            $0.montantPaye(variantes: variantes)
        }.reduce(0, +)
    }

    var manque: Double {
        max(0, totalGeneral - totalPaye)
    }

    var nombreParticipants: Int {
        orders.filter { !$0.lignes.isEmpty && !$0.nom.isEmpty }.count
    }

    var resteALivrer: Int {
        orders.filter { $0.estValide && !$0.estLivre }.count
    }

    // MARK: - Détails par variante

    func quantitePourVariante(_ nom: String) -> Double {
        orders.flatMap(\.lignes).filter { $0.variante == nom }.map(\.quantite).reduce(0, +)
    }

    func nombreCommandesPourVariante(_ nom: String) -> Int {
        orders.filter { $0.lignes.contains { $0.variante == nom && $0.quantite > 0 } }.count
    }

    func totalPourVariante(_ nom: String) -> Double {
        orders.filter(\.estValide).flatMap(\.lignes)
            .filter { $0.variante == nom }
            .compactMap { $0.total(variantes: variantes) }
            .reduce(0, +)
    }

    var nombreRegles: Int {
        orders.filter { $0.estValide && $0.estEntierementRegle(variantes: variantes) }.count
    }

    var nombreNonRegles: Int {
        orders.filter { $0.estValide && !$0.estEntierementRegle(variantes: variantes) }.count
    }

    var totalCheque: Double {
        orders.filter(\.estValide)
            .flatMap(\.reglements)
            .filter { $0.modePaiement == .cheque }
            .map(\.montant)
            .reduce(0, +)
    }

    var nombreCheques: Int {
        orders.filter(\.estValide)
            .flatMap(\.reglements)
            .filter { $0.modePaiement == .cheque }.count
    }

    var totalEspeces: Double {
        orders.filter(\.estValide)
            .flatMap(\.reglements)
            .filter { $0.modePaiement == .especes }
            .map(\.montant)
            .reduce(0, +)
    }

    var nombreEspeces: Int {
        orders.filter(\.estValide)
            .flatMap(\.reglements)
            .filter { $0.modePaiement == .especes }.count
    }

    // MARK: - Impayés (livré mais pas entièrement réglé)

    var totalImpayes: Double {
        orders.filter { $0.estValide && ($0.estLivre || $0.partiellementLivre) }
            .compactMap { $0.resteARegler(variantes: variantes) }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    var nombreImpayes: Int {
        orders.filter { $0.estValide && ($0.estLivre || $0.partiellementLivre) && $0.resteARegler(variantes: variantes) > 0 }.count
    }

    /// Tout est livré et tout est réglé (aucun impayé, aucune commande en cours)
    var toutEstFini: Bool {
        let commandesNonLivrees = orders.filter { $0.estValide && !$0.estLivre }
        let aDesImpayes = totalImpayes > 0
        let aDesLivraisons = orders.contains { $0.estLivre }
        return commandesNonLivrees.isEmpty && !aDesImpayes && aDesLivraisons
    }

    /// Tous les contacts avec un téléphone (pour passer commande)
    var tousLesNumeros: [String] {
        orders.filter { !$0.telephone.isEmpty }
            .map(\.telephone)
    }

    /// Uniquement ceux qui ont passé commande (pour avertir de l'arrivée)
    var numerosAvecCommande: [String] {
        orders.filter { !$0.telephone.isEmpty && !$0.lignes.isEmpty }
            .map(\.telephone)
    }

    // MARK: - Actions

    func ajouterCommande(categorieID: UUID? = nil) {
        var order = Order()
        order.categorieID = categorieID
        orders.append(order)
        save()
    }

    func supprimerCommande(at offsets: IndexSet) {
        orders.remove(atOffsets: offsets)
        save()
    }

    /// Importe des clients depuis un fichier texte (un par ligne).
    /// Format : "Nom;téléphone;catégorie" — téléphone et catégorie optionnels.
    /// Séparateur accepté : ";" ou ","
    /// Retourne le nombre de clients importés.
    func importerClientsDepuisFichier(url: URL) -> Int {
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let lignes = contenu.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var count = 0
        for ligne in lignes {
            let parts: [String]
            if ligne.contains(";") {
                parts = ligne.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if ligne.contains(",") {
                parts = ligne.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = [ligne]
            }
            let nom = parts[0]
            let tel = parts.count > 1 ? parts[1] : ""
            let catNom = parts.count > 2 ? parts[2] : ""
            guard !nom.isEmpty else { continue }

            // Éviter les doublons par nom
            if orders.contains(where: { $0.nom.localizedCaseInsensitiveCompare(nom) == .orderedSame }) {
                continue
            }

            // Résoudre ou créer la catégorie
            var catID: UUID? = nil
            if !catNom.isEmpty {
                if let existing = categories.first(where: { $0.nom.localizedCaseInsensitiveCompare(catNom) == .orderedSame }) {
                    catID = existing.id
                } else {
                    let nouvelle = CategorieClient(nom: catNom)
                    categories.append(nouvelle)
                    catID = nouvelle.id
                }
            }

            var order = Order()
            order.nom = nom
            order.telephone = tel
            order.categorieID = catID
            orders.append(order)
            count += 1
        }
        if count > 0 { save() }
        return count
    }

    func save() {
        if let data = try? JSONEncoder().encode(orders) {
            UserDefaults.standard.set(data, forKey: ordersKey)
        }
        UserDefaults.standard.set(titreCampagne, forKey: titreKey)
        UserDefaults.standard.set(uniteQuantite.rawValue, forKey: uniteKey)
        if let data = try? JSONEncoder().encode(variantes) {
            UserDefaults.standard.set(data, forKey: variantesKey)
        }
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
        UserDefaults.standard.set(telephoneVendeur, forKey: telVendeurKey)
    }

    // MARK: - Export récapitulatif PDF

    func genererPDF() -> Data {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale(identifier: "fr_FR")

        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor.darkGray
        ]
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let redAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor.red
        ]
        let greenAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1)
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var y: CGFloat = margin

            func checkPage() {
                if y > pageHeight - margin - 30 {
                    context.beginPage()
                    y = margin
                }
            }

            func drawLine(_ text: String, attr: [NSAttributedString.Key: Any], indent: CGFloat = 0) {
                checkPage()
                let nsText = text as NSString
                let rect = CGRect(x: margin + indent, y: y, width: contentWidth - indent, height: 200)
                let size = nsText.boundingRect(with: CGSize(width: contentWidth - indent, height: 200), options: .usesLineFragmentOrigin, attributes: attr, context: nil)
                nsText.draw(in: rect, withAttributes: attr)
                y += size.height + 4
            }

            func drawSeparator() {
                checkPage()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 8
            }

            context.beginPage()

            // Titre
            drawLine("RÉCAPITULATIF \(titreCampagne.uppercased())", attr: titleAttr)
            drawLine("Date : \(df.string(from: Date()))", attr: bodyAttr)
            let prixInfo = variantes.map { "\($0.nom): \(String(format: "%.2f", $0.prix)) €/\(labelUnite)" }.joined(separator: "  —  ")
            if !prixInfo.isEmpty { drawLine(prixInfo, attr: bodyAttr) }
            y += 8
            drawSeparator()

            // Détail par client
            drawLine("DÉTAIL PAR CLIENT", attr: headerAttr)
            y += 4

            for order in orders where !order.nom.isEmpty {
                checkPage()
                drawLine("▸ \(order.nom)" + (order.telephone.isEmpty ? "" : "  —  \(order.telephone)"), attr: headerAttr)

                if !order.lignes.isEmpty {
                    for ligne in order.lignes {
                        let montant = ligne.total(variantes: variantes) ?? 0
                        var detail = "Commande : \(formatQte(ligne.quantite)) \(ligne.variante)"
                        if let t = ligne.taille { detail += " · \(t)" }
                        if let c = ligne.couleur { detail += " · \(c)" }
                        detail += "  —  Montant : \(String(format: "%.2f", montant)) €"
                        if ligne.quantiteLivree > 0 {
                            detail += "  —  Livré : \(formatQte(ligne.quantiteLivree))"
                            if ligne.resteALivrer > 0 {
                                detail += " (reste \(formatQte(ligne.resteALivrer)))"
                            }
                        }
                        drawLine(detail, attr: bodyAttr, indent: 12)
                    }
                    if let totalClient = order.total(variantes: variantes) {
                        drawLine("Total : \(String(format: "%.2f", totalClient)) €", attr: headerAttr, indent: 12)
                    }
                }

                if order.estLivre {
                    drawLine("✓ LIVRÉ le \(order.dateLivraison.map { df.string(from: $0) } ?? "—")", attr: greenAttr, indent: 12)
                } else if order.partiellementLivre {
                    let pct = order.quantiteTotale > 0 ? Int(order.quantiteTotaleLivree / order.quantiteTotale * 100) : 0
                    drawLine("⏳ LIVRÉ PARTIELLEMENT (\(pct)%) depuis le \(order.dateLivraison.map { df.string(from: $0) } ?? "—")", attr: bodyAttr, indent: 12)
                }

                if !order.reglements.isEmpty {
                    for r in order.reglements {
                        drawLine("Réglé \(String(format: "%.2f", r.montant)) € — \(r.modePaiement.rawValue) le \(df.string(from: r.date))", attr: greenAttr, indent: 12)
                    }
                }

                let reste = order.resteARegler(variantes: variantes)
                if reste > 0 && (order.estLivre || order.partiellementLivre) {
                    drawLine("⚠️ RESTE DÛ : \(String(format: "%.2f", reste)) €", attr: redAttr, indent: 12)
                } else if reste > 0 {
                    drawLine("Non réglé : \(String(format: "%.2f", reste)) €", attr: redAttr, indent: 12)
                }

                y += 4
            }

            drawSeparator()

            // Résumé
            drawLine("RÉSUMÉ", attr: headerAttr)
            y += 4
            drawLine("Quantité totale : \(formatQte(totalQuantite))", attr: bodyAttr, indent: 8)
            for v in variantes {
                drawLine("\(v.nom) : \(formatQte(quantitePourVariante(v.nom))) · \(nombreCommandesPourVariante(v.nom)) cmd · \(String(format: "%.2f", totalPourVariante(v.nom))) €", attr: bodyAttr, indent: 12)
            }
            drawLine("Total général : \(String(format: "%.2f", totalGeneral)) €", attr: bodyAttr, indent: 8)
            drawLine("Total réglé : \(String(format: "%.2f", totalPaye)) €", attr: bodyAttr, indent: 8)
            drawLine("Chèques : \(String(format: "%.2f", totalCheque)) €  —  Espèces : \(String(format: "%.2f", totalEspeces)) €", attr: bodyAttr, indent: 8)
            if totalImpayes > 0 {
                drawLine("Impayés : \(String(format: "%.2f", totalImpayes)) €", attr: redAttr, indent: 8)
            }
            drawLine("Manque : \(String(format: "%.2f", manque)) €", attr: manque > 0 ? redAttr : greenAttr, indent: 8)
        }

        return data
    }

    func exporterRecapitulatif() -> URL? {
        let data = genererPDF()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        let nomFichier = "Recap_\(sanitized)_\(df.string(from: Date())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Export bon de commande groupé PDF

    func genererPDFCommande(afficherPrix: Bool = true, afficherClients: Bool = true) -> Data {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale(identifier: "fr_FR")

        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor.darkGray
        ]
        let subHeaderAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor(red: 0.05, green: 0.30, blue: 0.50, alpha: 1)
        ]
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let totalAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]

        // Regrouper toutes les lignes
        struct CleGroupe: Hashable {
            let variante: String
            let taille: String?
            let couleur: String?
        }
        struct DetailClient {
            let nom: String
            let quantite: Double
        }

        var groupes: [CleGroupe: [DetailClient]] = [:]
        for order in orders where order.estValide {
            for ligne in order.lignes where !ligne.variante.isEmpty && ligne.quantite > 0 {
                let cle = CleGroupe(variante: ligne.variante, taille: ligne.taille, couleur: ligne.couleur)
                let detail = DetailClient(nom: order.nom, quantite: ligne.quantite)
                groupes[cle, default: []].append(detail)
            }
        }

        // Trier par nom de variante
        let variantesTriees = variantes.map(\.nom)
        let clesTriees = groupes.keys.sorted { a, b in
            let ia = variantesTriees.firstIndex(of: a.variante) ?? Int.max
            let ib = variantesTriees.firstIndex(of: b.variante) ?? Int.max
            if ia != ib { return ia < ib }
            if a.taille != b.taille { return (a.taille ?? "") < (b.taille ?? "") }
            return (a.couleur ?? "") < (b.couleur ?? "")
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var y: CGFloat = margin

            func checkPage() {
                if y > pageHeight - margin - 30 {
                    context.beginPage()
                    y = margin
                }
            }

            func drawLine(_ text: String, attr: [NSAttributedString.Key: Any], indent: CGFloat = 0) {
                checkPage()
                let nsText = text as NSString
                let rect = CGRect(x: margin + indent, y: y, width: contentWidth - indent, height: 200)
                let size = nsText.boundingRect(with: CGSize(width: contentWidth - indent, height: 200), options: .usesLineFragmentOrigin, attributes: attr, context: nil)
                nsText.draw(in: rect, withAttributes: attr)
                y += size.height + 4
            }

            func drawSeparator() {
                checkPage()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 8
            }

            context.beginPage()

            // Titre
            drawLine("BON DE COMMANDE — \(titreCampagne.uppercased())", attr: titleAttr)
            drawLine("Date : \(df.string(from: Date()))", attr: bodyAttr)
            drawLine("Nombre de clients : \(nombreParticipants)  —  Quantité totale : \(formatQte(totalQuantite))", attr: bodyAttr)
            y += 8
            drawSeparator()

            // Regroupement par variante
            var varianteEnCours = ""
            var totalVariante: Double = 0

            for cle in clesTriees {
                guard let clients = groupes[cle] else { continue }
                let totalGroupe = clients.map(\.quantite).reduce(0, +)

                // Nouvelle variante : afficher le titre
                if cle.variante != varianteEnCours {
                    // Total de la variante précédente
                    if !varianteEnCours.isEmpty {
                        var totalLigne = "Total \(varianteEnCours) : \(formatQte(totalVariante))"
                        if afficherPrix, let prix = variantes.first(where: { $0.nom == varianteEnCours })?.prix {
                            totalLigne += "  —  \(String(format: "%.2f", totalVariante * prix)) €"
                        }
                        drawLine(totalLigne, attr: totalAttr, indent: 8)
                        y += 4
                        drawSeparator()
                    }
                    varianteEnCours = cle.variante
                    totalVariante = 0
                    var titre = "▸ \(cle.variante)"
                    if afficherPrix, let prix = variantes.first(where: { $0.nom == cle.variante })?.prix {
                        titre += "  —  \(String(format: "%.2f", prix)) €/\(labelUnite)"
                    }
                    drawLine(titre, attr: headerAttr)
                    y += 2
                }

                totalVariante += totalGroupe

                // Sous-groupe taille/couleur
                var sousGroupe = ""
                if let t = cle.taille, !t.isEmpty { sousGroupe += t }
                if let c = cle.couleur, !c.isEmpty {
                    if !sousGroupe.isEmpty { sousGroupe += " · " }
                    sousGroupe += c
                }

                if !sousGroupe.isEmpty {
                    var ligneGroupe = "\(sousGroupe)  —  \(formatQte(totalGroupe))"
                    if afficherPrix, let prix = variantes.first(where: { $0.nom == cle.variante })?.prix {
                        ligneGroupe += "  —  \(String(format: "%.2f", totalGroupe * prix)) €"
                    }
                    drawLine(ligneGroupe, attr: subHeaderAttr, indent: 12)
                } else {
                    var ligneTotal = "Total : \(formatQte(totalGroupe))"
                    if afficherPrix, let prix = variantes.first(where: { $0.nom == cle.variante })?.prix {
                        ligneTotal += "  —  \(String(format: "%.2f", totalGroupe * prix)) €"
                    }
                    drawLine(ligneTotal, attr: subHeaderAttr, indent: 12)
                }

                // Liste des clients
                if afficherClients {
                    let clientsTries = clients.sorted { $0.nom.localizedCompare($1.nom) == .orderedAscending }
                    for client in clientsTries {
                        drawLine("\(client.nom) : \(formatQte(client.quantite))", attr: bodyAttr, indent: 24)
                    }
                }
                y += 2
            }

            // Total de la dernière variante
            if !varianteEnCours.isEmpty {
                var ligneTotal = "Total \(varianteEnCours) : \(formatQte(totalVariante))"
                if afficherPrix, let prix = variantes.first(where: { $0.nom == varianteEnCours })?.prix {
                    ligneTotal += "  —  \(String(format: "%.2f", totalVariante * prix)) €"
                }
                drawLine(ligneTotal, attr: totalAttr, indent: 8)
                y += 4
                drawSeparator()
            }

            // Résumé global
            y += 4
            drawLine("RÉSUMÉ", attr: headerAttr)
            y += 4
            for v in variantes {
                let qte = quantitePourVariante(v.nom)
                let nb = nombreCommandesPourVariante(v.nom)
                var ligne = "\(v.nom) : \(formatQte(qte)) — \(nb) client\(nb > 1 ? "s" : "")"
                if afficherPrix { ligne += " — \(String(format: "%.2f", qte * v.prix)) €" }
                drawLine(ligne, attr: bodyAttr, indent: 8)
            }
            var totalLigne = "TOTAL : \(formatQte(totalQuantite))"
            if afficherPrix { totalLigne += "  —  \(String(format: "%.2f", totalGeneral)) €" }
            drawLine(totalLigne, attr: totalAttr, indent: 8)
        }

        return data
    }

    func exporterBonCommande(afficherPrix: Bool = true, afficherClients: Bool = true) -> URL? {
        let data = genererPDFCommande(afficherPrix: afficherPrix, afficherClients: afficherClients)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        var suffixe = "Commande"
        if afficherPrix && afficherClients { suffixe = "Commande_detail" }
        else if !afficherClients { suffixe = "Commande_fournisseur" }
        let nomFichier = "\(suffixe)_\(sanitized)_\(df.string(from: Date())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - PDF de distribution (par catégorie / client)

    func genererPDFDistribution() -> Data {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let catAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.white
        ]
        let clientAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ]
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let totalAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor(red: 0.05, green: 0.30, blue: 0.50, alpha: 1)
        ]

        // Grouper les commandes par catégorie
        struct CatSection {
            let titre: String
            var clients: [Order]
        }

        var sections: [CatSection] = []
        for cat in categories {
            let clients = orders.filter { $0.estValide && $0.categorieID == cat.id }
                .sorted { $0.nom.localizedCompare($1.nom) == .orderedAscending }
            if !clients.isEmpty {
                sections.append(CatSection(titre: cat.nom.isEmpty ? "Sans nom" : cat.nom, clients: clients))
            }
        }
        // Clients sans catégorie
        let sansCategorie = orders.filter { o in
            o.estValide && (o.categorieID == nil || !categories.contains(where: { $0.id == o.categorieID }))
        }.sorted { $0.nom.localizedCompare($1.nom) == .orderedAscending }
        if !sansCategorie.isEmpty {
            sections.append(CatSection(titre: categories.isEmpty ? "" : "Sans catégorie", clients: sansCategorie))
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var y: CGFloat = margin

            func checkPage(_ needed: CGFloat = 30) {
                if y > pageHeight - margin - needed {
                    context.beginPage()
                    y = margin
                }
            }

            func drawLine(_ text: String, attr: [NSAttributedString.Key: Any], indent: CGFloat = 0) {
                let nsText = text as NSString
                let size = nsText.boundingRect(with: CGSize(width: contentWidth - indent, height: 200), options: .usesLineFragmentOrigin, attributes: attr, context: nil)
                checkPage(size.height + 4)
                nsText.draw(in: CGRect(x: margin + indent, y: y, width: contentWidth - indent, height: size.height + 2), withAttributes: attr)
                y += size.height + 4
            }

            func drawCategoryBanner(_ text: String) {
                checkPage(28)
                let bannerRect = CGRect(x: margin, y: y, width: contentWidth, height: 22)
                UIColor(red: 0.05, green: 0.30, blue: 0.50, alpha: 1).setFill()
                UIBezierPath(roundedRect: bannerRect, cornerRadius: 6).fill()
                let nsText = text.uppercased() as NSString
                nsText.draw(in: CGRect(x: margin + 10, y: y + 3, width: contentWidth - 20, height: 18), withAttributes: catAttr)
                y += 28
            }

            func drawSeparator() {
                checkPage(8)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 6
            }

            context.beginPage()

            // Titre
            let df = DateFormatter()
            df.dateStyle = .short
            df.locale = Locale(identifier: "fr_FR")
            drawLine("FICHE DE DISTRIBUTION — \(titreCampagne.uppercased())", attr: titleAttr)
            drawLine("Date : \(df.string(from: Date()))  —  \(nombreParticipants) client\(nombreParticipants > 1 ? "s" : "")  —  \(formatQte(totalQuantite))", attr: bodyAttr)
            y += 8

            for section in sections {
                if !section.titre.isEmpty {
                    drawCategoryBanner(section.titre)
                }

                for client in section.clients {
                    // Estimer la hauteur nécessaire pour garder le client groupé
                    let lignesCount = client.lignes.filter { $0.quantite > 0 }.count
                    checkPage(CGFloat(lignesCount + 2) * 16)

                    // Nom du client + checkbox
                    drawLine("☐  \(client.nom.isEmpty ? "Sans nom" : client.nom)", attr: clientAttr, indent: 4)

                    for ligne in client.lignes where ligne.quantite > 0 {
                        var detail = "\(formatQte(ligne.quantite))  \(ligne.variante)"
                        if let t = ligne.taille, !t.isEmpty { detail += "  ·  \(t)" }
                        if let c = ligne.couleur, !c.isEmpty { detail += "  ·  \(c)" }
                        drawLine(detail, attr: bodyAttr, indent: 24)
                    }

                    if let total = client.total(variantes: variantes) {
                        drawLine("→ \(String(format: "%.2f €", total))", attr: totalAttr, indent: 24)
                    }
                    y += 2
                }

                drawSeparator()
            }

            // Résumé en bas
            y += 4
            drawLine("TOTAL : \(formatQte(totalQuantite))  —  \(String(format: "%.2f €", totalGeneral))", attr: titleAttr)
        }

        return data
    }

    func exporterDistribution() -> URL? {
        let data = genererPDFDistribution()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        let nomFichier = "Distribution_\(sanitized)_\(df.string(from: Date())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func remiseAZero() {
        for i in orders.indices {
            orders[i].remiseAZero()
        }
        save()
    }

    // MARK: - Sauvegarde / Chargement campagne JSON

    private var campagnesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Campagnes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func rafraichirListeCampagnes() {
        let fm = FileManager.default
        let dir = campagnesDirectory
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        campagnesSauvegardees = files
            .filter { $0.pathExtension == "json" }
            .compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding }
            .sorted()
    }

    func sauvegarderCampagne(nom: String) -> URL? {
        let data = CampagneData(
            titreCampagne: titreCampagne,
            uniteQuantite: uniteQuantite,
            variantes: variantes,
            categories: categories,
            orders: orders,
            telephoneVendeur: telephoneVendeur
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(data) else { return nil }
        let sanitized = nom.replacingOccurrences(of: "/", with: "-")
        let url = campagnesDirectory.appendingPathComponent("\(sanitized).json")
        do {
            try jsonData.write(to: url, options: .atomic)
            rafraichirListeCampagnes()
            return url
        } catch {
            return nil
        }
    }

    func chargerCampagne(nom: String) -> Bool {
        let sanitized = nom.replacingOccurrences(of: "/", with: "-")
        let url = campagnesDirectory.appendingPathComponent("\(sanitized).json")
        return chargerCampagne(depuis: url)
    }

    func chargerCampagne(depuis url: URL) -> Bool {
        guard let jsonData = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let campagne = try? decoder.decode(CampagneData.self, from: jsonData) else { return false }
        titreCampagne = campagne.titreCampagne
        uniteQuantite = campagne.uniteQuantite
        variantes = campagne.variantes
        categories = campagne.categories
        orders = campagne.orders
        telephoneVendeur = campagne.telephoneVendeur ?? ""
        save()
        return true
    }

    func supprimerCampagne(nom: String) {
        let sanitized = nom.replacingOccurrences(of: "/", with: "-")
        let url = campagnesDirectory.appendingPathComponent("\(sanitized).json")
        try? FileManager.default.removeItem(at: url)
        rafraichirListeCampagnes()
    }

    /// Exporte la campagne actuelle en JSON dans un fichier temporaire (pour partage)
    func exporterCampagneJSON() -> URL? {
        let data = CampagneData(
            titreCampagne: titreCampagne,
            uniteQuantite: uniteQuantite,
            variantes: variantes,
            categories: categories,
            orders: orders,
            telephoneVendeur: telephoneVendeur
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(data) else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        let nomFichier = "Campagne_\(sanitized)_\(df.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            try jsonData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: ordersKey),
           let decoded = try? JSONDecoder().decode([Order].self, from: data) {
            orders = decoded
        }
        titreCampagne = UserDefaults.standard.string(forKey: titreKey) ?? "Coquilles"
        if let uniteRaw = UserDefaults.standard.string(forKey: uniteKey),
           let unite = UniteQuantite(rawValue: uniteRaw) {
            uniteQuantite = unite
        }
        if let data = UserDefaults.standard.data(forKey: variantesKey),
           let decoded = try? JSONDecoder().decode([Variante].self, from: data) {
            variantes = decoded
        }
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([CategorieClient].self, from: data) {
            categories = decoded
        }
        telephoneVendeur = UserDefaults.standard.string(forKey: telVendeurKey) ?? ""
        migrateIfNeeded()
        rafraichirListeCampagnes()
    }

    /// Migration des anciennes commandes vers le nouveau modèle partiel
    private func migrateIfNeeded() {
        var needsSave = false
        for i in orders.indices {
            // Migrer livre → quantiteLivree sur chaque ligne
            if orders[i].livre && orders[i].lignes.allSatisfy({ $0.quantiteLivree == 0 }) && !orders[i].lignes.isEmpty {
                for j in orders[i].lignes.indices {
                    orders[i].lignes[j].quantiteLivree = orders[i].lignes[j].quantite
                }
                needsSave = true
            }
            // Migrer modePaiement → reglements
            if orders[i].modePaiement != nil && orders[i].reglements.isEmpty {
                if let total = orders[i].total(variantes: variantes) {
                    let montant = total - orders[i].impaye
                    if montant > 0 {
                        orders[i].reglements.append(Reglement(
                            montant: montant,
                            modePaiement: orders[i].modePaiement!,
                            date: orders[i].dateReglement ?? Date()
                        ))
                        needsSave = true
                    }
                }
            }
            // Migrer impayé déjà réglé
            if let mode = orders[i].impayeModePaiement, orders[i].impaye == 0,
               let date = orders[i].dateReglementImpaye,
               !orders[i].reglements.contains(where: { $0.date == date }) {
                if let total = orders[i].total(variantes: variantes) {
                    let montantImpaye = total - orders[i].reglements.map(\.montant).reduce(0, +)
                    if montantImpaye > 0 {
                        orders[i].reglements.append(Reglement(
                            montant: montantImpaye,
                            modePaiement: mode,
                            date: date
                        ))
                        needsSave = true
                    }
                }
            }
        }
        if needsSave { save() }
    }

    // MARK: - Génération page web commande

    /// URL de base de la page GitHub Pages
    private let pagesBaseURL = "https://boboul-cloud.github.io/coquilles/"

    /// Génère un lien web vers la page de commande hébergée sur GitHub Pages
    /// Format compact : "2|titre|unite|telVendeur|nom~prix~t1,t2~c1,c2|..." en base64url
    func genererLienWebCommande() -> URL? {
        let parts = variantes.filter { !$0.nom.isEmpty }.map { v in
            "\(v.nom)~\(v.prix)~\(v.tailles.joined(separator: ","))~\(v.couleurs.joined(separator: ","))"
        }
        guard !parts.isEmpty else { return nil }
        let payload = "2|\(titreCampagne)|\(uniteQuantite.rawValue)|\(telephoneVendeur)|\(parts.joined(separator: "|"))"
        guard let raw = payload.data(using: .utf8) else { return nil }

        let encoded = raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: pagesBaseURL + "#" + encoded)
    }

    private func escaperJS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Normalise un numéro de téléphone pour la comparaison
    private func normaliserTelephone(_ tel: String) -> String {
        let digits = tel.filter(\.isNumber)
        // +33612345678 → 0612345678
        if digits.hasPrefix("33") && digits.count == 11 {
            return "0" + digits.dropFirst(2)
        }
        return digits
    }

    /// Importe une commande depuis les données encodées dans un deep link. Retourne le nom du client importé, ou nil en cas d'échec.
    func importerCommandeDepuisURL(_ url: URL) -> String? {
        guard url.scheme == "coquilles", url.host == "order" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let decoded = Data(base64Encoded: dataParam),
              let jsonString = String(data: decoded, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8)
        else { return nil }

        struct CommandeWeb: Decodable {
            let n: String       // nom
            let p: String?      // téléphone
            let l: [LigneWeb]   // lignes
        }
        struct LigneWeb: Decodable {
            let v: String       // variante
            let q: Double       // quantité
            let t: String?      // taille
            let c: String?      // couleur
        }

        guard let commande = try? JSONDecoder().decode(CommandeWeb.self, from: jsonData) else { return nil }

        // Vérifier si un client avec ce téléphone existe déjà
        let tel = commande.p ?? ""
        let telNorm = normaliserTelephone(tel)
        if let index = orders.firstIndex(where: { !telNorm.isEmpty && normaliserTelephone($0.telephone) == telNorm }) {
            // Ajouter les lignes à la commande existante
            for l in commande.l {
                let ligne = LigneCommande(
                    variante: l.v,
                    taille: l.t,
                    couleur: l.c,
                    quantite: l.q
                )
                orders[index].lignes.append(ligne)
            }
            if orders[index].nom.isEmpty {
                orders[index].nom = commande.n
            }
        } else {
            var order = Order()
            order.nom = commande.n
            order.telephone = tel
            order.lignes = commande.l.map { l in
                LigneCommande(
                    variante: l.v,
                    taille: l.t,
                    couleur: l.c,
                    quantite: l.q
                )
            }
            orders.append(order)
        }
        save()
        return commande.n.isEmpty ? "Client" : commande.n
    }
}
