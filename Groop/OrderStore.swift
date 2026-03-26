//
//  OrderStore.swift
//  Groop
//
//  Created by Robert Oulhen on 11/03/2026.
//

import Foundation
import Combine
import SwiftUI
import UIKit
import Vision
import PDFKit

/// Snapshot complet d'une campagne, exportable en JSON.
struct CampagneData: Codable {
    var titreCampagne: String
    var uniteQuantite: UniteQuantite
    var variantes: [Variante]
    var categories: [CategorieClient]
    var orders: [Order]
    var telephoneVendeur: String?
}

/// Backup multi-campagne : campagne active + toutes les campagnes sauvegardées.
struct MultiCampagneBackup: Codable {
    var dateBackup: Date
    var campagneActive: CampagneData
    var campagnesSauvegardees: [String: CampagneData]
}

/// Info résumée d'un backup stocké localement.
struct BackupInfo: Identifiable {
    var id: String { nomFichier }
    var nomFichier: String
    var date: Date
    var dateFormatee: String
}

class OrderStore: ObservableObject {
    @Published var orders: [Order] = []
    @Published var titreCampagne: String = "Groop"
    @Published var uniteQuantite: UniteQuantite = .kg
    @Published var variantes: [Variante] = []
    @Published var categories: [CategorieClient] = []
    @Published var campagnesSauvegardees: [String] = []
    @Published var backups: [BackupInfo] = []
    @Published var telephoneVendeur: String = ""

    private let ordersKey = "savedOrders"
    private let titreKey = "campagneTitre"
    private let uniteKey = "campagneUnite"
    private let variantesKey = "campagneVariantes"
    private let categoriesKey = "campagneCategories"
    private let telVendeurKey = "campagneTelVendeur"

    init() {
        load()
        rafraichirListeBackups()
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
        orders.filter { !$0.lignes.isEmpty && !$0.nomComplet.isEmpty }.count
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
        let validOrders = orders.filter(\.estValide)
        let cheques = validOrders.flatMap(\.reglements).filter { $0.modePaiement == .cheque }
        return cheques.map(\.montant).reduce(0, +)
    }

    var nombreCheques: Int {
        let validOrders = orders.filter(\.estValide)
        return validOrders.flatMap(\.reglements).filter { $0.modePaiement == .cheque }.count
    }

    var totalEspeces: Double {
        let validOrders = orders.filter(\.estValide)
        let especes = validOrders.flatMap(\.reglements).filter { $0.modePaiement == .especes }
        return especes.map(\.montant).reduce(0, +)
    }

    var nombreEspeces: Int {
        let validOrders = orders.filter(\.estValide)
        return validOrders.flatMap(\.reglements).filter { $0.modePaiement == .especes }.count
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

    /// Clients impayés (livrés mais pas entièrement réglés) avec un téléphone
    var clientsImpayes: [Order] {
        orders.filter { $0.estValide && $0.estLivre && $0.resteARegler(variantes: variantes) > 0 && !$0.telephone.isEmpty }
    }

    /// Clients dont la commande n'a pas encore été livrée, avec un téléphone
    var clientsNonLivres: [Order] {
        orders.filter { $0.estValide && !$0.estLivre && !$0.telephone.isEmpty }
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

    /// Exporte la liste des clients au format texte.
    /// - `separerNomPrenom`: si true → Prénom;Nom;Téléphone (compatible autre app)
    /// - `separerNomPrenom`: si false → Nom;Téléphone;Catégorie (format Groop)
    /// - `categorieID`: si défini, exporte uniquement les clients de cette catégorie
    func exporterClientsFichier(separerNomPrenom: Bool = false, categorieID: UUID? = nil) -> URL? {
        let sourceOrders: [Order]
        if let catID = categorieID {
            sourceOrders = orders.filter { $0.categorieID == catID }
        } else {
            sourceOrders = orders
        }
        var lignes: [String] = []
        // En-tête catégorie pour le format Temps de Jeu
        if separerNomPrenom, let catID = categorieID,
           let catNom = categories.first(where: { $0.id == catID })?.nom, !catNom.isEmpty {
            lignes.append("# Catégorie: \(catNom)")
        }
        for order in sourceOrders {
            guard !order.nomComplet.isEmpty else { continue }
            let tel = order.telephone
            if separerNomPrenom {
                lignes.append([order.prenom, order.nom, tel].joined(separator: ";"))
            } else {
                let catNom = categories.first(where: { $0.id == order.categorieID })?.nom ?? ""
                lignes.append([order.nomComplet, tel, catNom].joined(separator: ";"))
            }
        }
        // Vérifier qu'il y a au moins une ligne de données (hors en-tête)
        let dataLines = lignes.filter { !$0.hasPrefix("#") }
        guard !dataLines.isEmpty else { return nil }
        let contenu = lignes.joined(separator: "\n")
        let tmpDir = FileManager.default.temporaryDirectory
        let fileName = titreCampagne.isEmpty ? "clients" : titreCampagne.replacingOccurrences(of: " ", with: "_")
        let catSuffix: String
        if let catID = categorieID, let catNom = categories.first(where: { $0.id == catID })?.nom {
            catSuffix = "_" + catNom.replacingOccurrences(of: " ", with: "_")
        } else {
            catSuffix = ""
        }
        let suffix = separerNomPrenom ? "_clients_pntel\(catSuffix)" : "_clients\(catSuffix)"
        let url = tmpDir.appendingPathComponent("\(fileName)\(suffix).txt")
        do {
            try contenu.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Détecte si une chaîne ressemble à un numéro de téléphone.
    private func ressembleATelephone(_ s: String) -> Bool {
        let chiffres = s.filter { $0.isNumber }
        return chiffres.count >= 4
    }

    /// Importe des clients depuis un fichier texte (un par ligne).
    /// Formats détectés automatiquement :
    /// - "Prénom;Nom;Téléphone" (si le 2e champ n'est pas un numéro)
    /// - "Nom;Téléphone;Catégorie" (si le 2e champ est un numéro)
    /// Séparateur accepté : ";" ou ","
    /// Retourne le nombre de clients importés.
    func importerClientsDepuisFichier(url: URL) -> Int {
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let lignes = contenu.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Détecter le format sur la première ligne
        // Format A : "Prénom;Nom;Téléphone" → le 2e champ est un nom (non vide, pas un tel), le 3e est un tel ou vide
        // Format B : "Nom complet;Téléphone;Catégorie" → le 2e champ est un tel (ou vide avec 3e champ non-tel)
        var formatPrenomNomTel = false
        if let premiere = lignes.first?.trimmingCharacters(in: .whitespaces),
           !premiere.hasPrefix("#") {
            let p: [String]
            if premiere.contains(";") {
                p = premiere.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if premiere.contains(",") {
                p = premiere.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                p = [premiere]
            }
            if p.count >= 3 {
                let champ2 = p[1]
                let champ3 = p[2]
                // C'est Prénom;Nom;Téléphone si :
                // - le 2e champ n'est pas un numéro ET n'est pas vide
                // - ET le 3e champ ressemble à un tel (ou est vide)
                if !champ2.isEmpty && !ressembleATelephone(champ2)
                    && (champ3.isEmpty || ressembleATelephone(champ3)) {
                    formatPrenomNomTel = true
                }
            }
        }

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

            let importPrenom: String
            let importNom: String
            let tel: String
            let catNom: String

            if formatPrenomNomTel && parts.count >= 2 {
                // Format : Prénom;Nom;Téléphone
                importPrenom = parts[0]
                importNom = parts.count > 1 ? parts[1] : ""
                tel = parts.count > 2 ? parts[2] : ""
                catNom = ""
            } else {
                // Format : Nom;Téléphone;Catégorie → séparer au premier espace
                let composants = parts[0].split(separator: " ", maxSplits: 1).map(String.init)
                importPrenom = composants.first ?? parts[0]
                importNom = composants.count > 1 ? composants[1] : ""
                tel = parts.count > 1 ? parts[1] : ""
                catNom = parts.count > 2 ? parts[2] : ""
            }
            let nomComplet = [importPrenom, importNom].filter { !$0.isEmpty }.joined(separator: " ")
            guard !nomComplet.isEmpty else { continue }

            // Éviter les doublons par nom complet
            if orders.contains(where: { $0.nomComplet.localizedCaseInsensitiveCompare(nomComplet) == .orderedSame }) {
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
            order.prenom = importPrenom
            order.nom = importNom
            order.telephone = tel
            order.categorieID = catID
            orders.append(order)
            count += 1
        }
        if count > 0 { save() }
        return count
    }

    /// Réinitialise la campagne. Si garderClients est true, conserve les noms/téléphones mais vide leurs commandes et paiements.
    func nouvelleCampagne(garderClients: Bool) {
        titreCampagne = ""
        uniteQuantite = .kg
        variantes = []
        categories = []
        telephoneVendeur = ""
        if garderClients {
            for i in orders.indices {
                orders[i].lignes = []
                orders[i].reglements = []
                orders[i].modePaiement = nil
                orders[i].impaye = 0
                orders[i].impayeModePaiement = nil
                orders[i].livre = false
                orders[i].dateLivraison = nil
                orders[i].dateReglement = nil
                orders[i].dateReglementImpaye = nil
                orders[i].categorieID = nil
            }
        } else {
            orders = []
        }
        save()
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
            let prixInfo = variantes.map { v in
                var label = "\(v.nom): \(String(format: "%.2f", v.prix)) €/\(labelUnite)"
                if !v.prixTailles.isEmpty {
                    let taillesPrix = v.tailles.compactMap { t in
                        v.prixTailles[t].map { "\(t): \(String(format: "%.2f", $0)) €" }
                    }
                    if !taillesPrix.isEmpty { label += " (\(taillesPrix.joined(separator: ", ")))" }
                }
                return label
            }.joined(separator: "  —  ")
            if !prixInfo.isEmpty { drawLine(prixInfo, attr: bodyAttr) }
            y += 8
            drawSeparator()

            // Détail par client
            drawLine("DÉTAIL PAR CLIENT", attr: headerAttr)
            y += 4

            for order in orders where !order.nomComplet.isEmpty {
                checkPage()
                drawLine("▸ \(order.nomComplet)" + (order.telephone.isEmpty ? "" : "  —  \(order.telephone)"), attr: headerAttr)

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
                let detail = DetailClient(nom: order.nomComplet, quantite: ligne.quantite)
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
            var totalMontantVariante: Double = 0

            for cle in clesTriees {
                guard let clients = groupes[cle] else { continue }
                let totalGroupe = clients.map(\.quantite).reduce(0, +)

                // Nouvelle variante : afficher le titre
                if cle.variante != varianteEnCours {
                    // Total de la variante précédente
                    if !varianteEnCours.isEmpty {
                        var totalLigne = "Total \(varianteEnCours) : \(formatQte(totalVariante))"
                        if afficherPrix {
                            totalLigne += "  —  \(String(format: "%.2f", totalMontantVariante)) €"
                        }
                        drawLine(totalLigne, attr: totalAttr, indent: 8)
                        y += 4
                        drawSeparator()
                    }
                    varianteEnCours = cle.variante
                    totalVariante = 0
                    totalMontantVariante = 0
                    var titre = "▸ \(cle.variante)"
                    if afficherPrix, let v = variantes.first(where: { $0.nom == cle.variante }) {
                        titre += "  —  \(String(format: "%.2f", v.prix)) €/\(labelUnite)"
                    }
                    drawLine(titre, attr: headerAttr)
                    y += 2
                }

                totalVariante += totalGroupe
                let prixEffectif = variantes.first(where: { $0.nom == cle.variante })?.prixPourTaille(cle.taille) ?? 0
                totalMontantVariante += totalGroupe * prixEffectif

                // Sous-groupe taille/couleur
                var sousGroupe = ""
                if let t = cle.taille, !t.isEmpty { sousGroupe += t }
                if let c = cle.couleur, !c.isEmpty {
                    if !sousGroupe.isEmpty { sousGroupe += " · " }
                    sousGroupe += c
                }

                if !sousGroupe.isEmpty {
                    var ligneGroupe = "\(sousGroupe)  —  \(formatQte(totalGroupe))"
                    if afficherPrix {
                        ligneGroupe += "  —  \(String(format: "%.2f", totalGroupe * prixEffectif)) €"
                    }
                    drawLine(ligneGroupe, attr: subHeaderAttr, indent: 12)
                } else {
                    var ligneTotal = "Total : \(formatQte(totalGroupe))"
                    if afficherPrix {
                        ligneTotal += "  —  \(String(format: "%.2f", totalGroupe * prixEffectif)) €"
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
                if afficherPrix {
                    ligneTotal += "  —  \(String(format: "%.2f", totalMontantVariante)) €"
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
                let totalV = totalPourVariante(v.nom)
                var ligne = "\(v.nom) : \(formatQte(qte)) — \(nb) client\(nb > 1 ? "s" : "")"
                if afficherPrix { ligne += " — \(String(format: "%.2f", totalV)) €" }
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

    // MARK: - Export CSV bon de commande

    func exporterBonCommandeCSV() -> URL? {
        let sep = ";"
        var lignesCSV: [String] = []
        lignesCSV.append(["Variante", "Taille", "Couleur", "Client", "Quantité", "Prix unitaire", "Total"].joined(separator: sep))

        for order in orders where !order.nomComplet.isEmpty && !order.lignes.isEmpty {
            for ligne in order.lignes where !ligne.variante.isEmpty && ligne.quantite > 0 {
                let v = variantes.first(where: { $0.nom == ligne.variante })
                let pu = v?.prixPourTaille(ligne.taille) ?? 0
                let total = ligne.quantite * pu
                let row = [
                    csvEscape(ligne.variante),
                    csvEscape(ligne.taille ?? ""),
                    csvEscape(ligne.couleur ?? ""),
                    csvEscape(order.nomComplet),
                    String(format: "%.2f", ligne.quantite).replacingOccurrences(of: ".", with: ","),
                    String(format: "%.2f", pu).replacingOccurrences(of: ".", with: ","),
                    String(format: "%.2f", total).replacingOccurrences(of: ".", with: ",")
                ]
                lignesCSV.append(row.joined(separator: sep))
            }
        }

        let contenu = lignesCSV.joined(separator: "\n")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        let nomFichier = "Commande_\(sanitized)_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            // BOM UTF-8 pour qu'Excel détecte correctement l'encodage
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(contenu.data(using: .utf8)!)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: - Export CSV campagne (variantes/tailles/prix)

    func exporterCampagneCSV() -> URL? {
        let sep = ";"
        var lignesCSV: [String] = []
        lignesCSV.append(["Variante", "Taille", "Couleur", "Prix"].joined(separator: sep))

        for v in variantes where !v.nom.isEmpty {
            if v.tailles.isEmpty && v.couleurs.isEmpty {
                let row = [
                    csvEscape(v.nom),
                    "",
                    "",
                    String(format: "%.2f", v.prix).replacingOccurrences(of: ".", with: ",")
                ]
                lignesCSV.append(row.joined(separator: sep))
            } else if v.couleurs.isEmpty {
                for t in v.tailles {
                    let p = v.prixPourTaille(t)
                    let row = [
                        csvEscape(v.nom),
                        csvEscape(t),
                        "",
                        String(format: "%.2f", p).replacingOccurrences(of: ".", with: ",")
                    ]
                    lignesCSV.append(row.joined(separator: sep))
                }
            } else if v.tailles.isEmpty {
                for c in v.couleurs {
                    let row = [
                        csvEscape(v.nom),
                        "",
                        csvEscape(c),
                        String(format: "%.2f", v.prix).replacingOccurrences(of: ".", with: ",")
                    ]
                    lignesCSV.append(row.joined(separator: sep))
                }
            } else {
                for t in v.tailles {
                    for c in v.couleurs {
                        let p = v.prixPourTaille(t)
                        let row = [
                            csvEscape(v.nom),
                            csvEscape(t),
                            csvEscape(c),
                            String(format: "%.2f", p).replacingOccurrences(of: ".", with: ",")
                        ]
                        lignesCSV.append(row.joined(separator: sep))
                    }
                }
            }
        }

        guard lignesCSV.count > 1 else { return nil }

        let contenu = lignesCSV.joined(separator: "\n")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sanitized = titreCampagne.replacingOccurrences(of: " ", with: "_")
        let nomFichier = "Campagne_\(sanitized)_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        do {
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(contenu.data(using: .utf8)!)
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
                .sorted { $0.nomComplet.localizedCompare($1.nomComplet) == .orderedAscending }
            if !clients.isEmpty {
                sections.append(CatSection(titre: cat.nom.isEmpty ? "Sans nom" : cat.nom, clients: clients))
            }
        }
        // Clients sans catégorie
        let sansCategorie = orders.filter { o in
            o.estValide && (o.categorieID == nil || !categories.contains(where: { $0.id == o.categorieID }))
        }.sorted { $0.nomComplet.localizedCompare($1.nomComplet) == .orderedAscending }
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
                    drawLine("☐  \(client.nomComplet.isEmpty ? "Sans nom" : client.nomComplet)", attr: clientAttr, indent: 4)

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

    /// Sauvegarde complète : campagne active + toutes les campagnes sauvegardées.
    func sauvegarderToutesCampagnes() -> URL? {
        let active = CampagneData(
            titreCampagne: titreCampagne,
            uniteQuantite: uniteQuantite,
            variantes: variantes,
            categories: categories,
            orders: orders,
            telephoneVendeur: telephoneVendeur
        )
        var sauvegardees: [String: CampagneData] = [:]
        let fm = FileManager.default
        let dir = campagnesDirectory
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let campagne = try? decoder.decode(CampagneData.self, from: data),
               let nom = file.deletingPathExtension().lastPathComponent.removingPercentEncoding {
                sauvegardees[nom] = campagne
            }
        }
        let backup = MultiCampagneBackup(
            dateBackup: Date(),
            campagneActive: active,
            campagnesSauvegardees: sauvegardees
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(backup) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateStr = formatter.string(from: Date())
        let url = backupsDirectory.appendingPathComponent("Backup-\(dateStr).json")
        do {
            try jsonData.write(to: url, options: .atomic)
            rafraichirListeBackups()
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Backups locaux

    private var backupsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func rafraichirListeBackups() {
        let fm = FileManager.default
        let dir = backupsDirectory
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        backups = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BackupInfo? in
                let nom = url.deletingPathExtension().lastPathComponent
                let dateStr = nom.replacingOccurrences(of: "Backup-", with: "")
                let date = formatter.date(from: dateStr) ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return BackupInfo(nomFichier: nom, date: date, dateFormatee: displayFormatter.string(from: date))
            }
            .sorted { $0.date > $1.date }
    }

    func restaurerBackup(info: BackupInfo) -> Int {
        let url = backupsDirectory.appendingPathComponent("\(info.nomFichier).json")
        return restaurerToutesCampagnes(depuis: url)
    }

    func supprimerBackup(info: BackupInfo) {
        let url = backupsDirectory.appendingPathComponent("\(info.nomFichier).json")
        try? FileManager.default.removeItem(at: url)
        rafraichirListeBackups()
    }

    /// Restaure un backup multi-campagne : écrase la campagne active et toutes les sauvegardes.
    func restaurerToutesCampagnes(depuis url: URL) -> Int {
        guard let jsonData = try? Data(contentsOf: url) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(MultiCampagneBackup.self, from: jsonData) else { return 0 }
        // Restaurer la campagne active
        titreCampagne = backup.campagneActive.titreCampagne
        uniteQuantite = backup.campagneActive.uniteQuantite
        variantes = backup.campagneActive.variantes
        categories = backup.campagneActive.categories
        orders = backup.campagneActive.orders
        telephoneVendeur = backup.campagneActive.telephoneVendeur ?? ""
        save()
        // Restaurer les campagnes sauvegardées
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        for (nom, campagne) in backup.campagnesSauvegardees {
            if let data = try? encoder.encode(campagne) {
                let sanitized = nom.replacingOccurrences(of: "/", with: "-")
                let fileURL = campagnesDirectory.appendingPathComponent("\(sanitized).json")
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        rafraichirListeCampagnes()
        return max(1, backup.campagnesSauvegardees.count)
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
        titreCampagne = UserDefaults.standard.string(forKey: titreKey) ?? "Groop"
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
            // Migrer nom unique → prenom + nom (ancien format sans champ prenom)
            if orders[i].prenom.isEmpty && !orders[i].nom.isEmpty {
                let composants = orders[i].nom.split(separator: " ", maxSplits: 1).map(String.init)
                if composants.count > 1 {
                    orders[i].prenom = composants[0]
                    orders[i].nom = composants[1]
                    needsSave = true
                } else {
                    // Un seul mot → mettre en prénom
                    orders[i].prenom = orders[i].nom
                    orders[i].nom = ""
                    needsSave = true
                }
            }
        }
        if needsSave { save() }
    }

    // MARK: - Génération page web commande

    /// URL de base de la page GitHub Pages
    private let pagesBaseURL = "https://boboul-cloud.github.io/groop/"

    /// Génère un lien web vers la page de commande hébergée sur GitHub Pages
    /// Format compact : "2|titre|unite|telVendeur|nom~prix~t1,t2~c1,c2|..." en base64url
    func genererLienWebCommande() -> URL? {
        let parts = variantes.filter { !$0.nom.isEmpty }.map { v in
            let taillesParts = v.tailles.map { t in
                if let p = v.prixTailles[t] {
                    return "\(t):\(p)"
                }
                return t
            }
            return "\(v.nom)~\(v.prix)~\(taillesParts.joined(separator: ";"))~\(v.couleurs.joined(separator: ";"))"
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

    /// Retourne un doublon potentiel pour une commande (même téléphone ou nom identique, en excluant cette commande elle-même)
    func doublonPour(_ order: Order) -> Order? {
        let telNorm = normaliserTelephone(order.telephone)
        let nomNorm = order.nomComplet.lowercased().trimmingCharacters(in: .whitespaces)
        return orders.first { autre in
            guard autre.id != order.id else { return false }
            if !telNorm.isEmpty && normaliserTelephone(autre.telephone) == telNorm { return true }
            let autreNom = autre.nomComplet.lowercased().trimmingCharacters(in: .whitespaces)
            if !nomNorm.isEmpty && autreNom == nomNorm { return true }
            return false
        }
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

    // MARK: - Import commandes depuis fichier CSV/TXT

    /// Résultat de l'import de commandes.
    struct ImportCommandesResult {
        var commandesCreees: Int = 0
        var lignesAjoutees: Int = 0
        var variantesCrees: Int = 0
        var prixImportes: Int = 0
        var erreurs: [String] = []
        var diagnosticIA: String = ""
    }

    /// Importe des commandes depuis un fichier CSV/TXT.
    /// Détecte automatiquement les colonnes via la ligne d'en-tête.
    /// Colonnes reconnues : Client/Nom/Prénom, Téléphone/Tel, Variante/Produit, Taille, Couleur, Quantité/Qté, Catégorie.
    /// Les lignes du même client sont regroupées dans une seule commande.
    /// Retourne un résumé de l'import.
    func importerCommandesDepuisFichier(url: URL) -> ImportCommandesResult {
        var result = ImportCommandesResult()
        var contenu: String
        if let c = try? String(contentsOf: url, encoding: .utf8) {
            contenu = c
        } else if let c = try? String(contentsOf: url, encoding: .isoLatin1) {
            contenu = c
        } else {
            result.erreurs.append("Impossible de lire le fichier.")
            return result
        }

        // 1) Tenter le parsing CSV classique (avec en-tête)
        let csvResult = parseCommandesCSV(contenu)
        if csvResult.lignesAjoutees > 0 || csvResult.variantesCrees > 0 {
            return csvResult
        }

        // 2) Fallback : parsing intelligent (texte brut de PDF copié-collé)
        if let produits = AITriageService.shared.parserDirectement(contenu) {
            var iaResult = appliquerProduitsIA(produits)
            iaResult.diagnosticIA = AITriageService.shared.dernierDiagnostic
            if iaResult.variantesCrees > 0 || iaResult.prixImportes > 0 {
                return iaResult
            }
        }

        // 3) Rien n'a marché — retourner le résultat CSV (avec ses erreurs éventuelles)
        return csvResult
    }

    private func parseCommandesCSV(_ contenu: String) -> ImportCommandesResult {
        var result = ImportCommandesResult()

        // Supprimer le BOM UTF-8 si présent
        let clean = contenu.hasPrefix("\u{FEFF}") ? String(contenu.dropFirst()) : contenu

        let lignes = clean.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lignes.isEmpty else {
            result.erreurs.append("Le fichier est vide ou ne contient aucune ligne exploitable.")
            return result
        }

        // Détecter le séparateur (tab, ;, ,, espaces multiples)
        let sep: String
        let premiereLigne = lignes[0]
        let tabCount = premiereLigne.components(separatedBy: "\t").count
        let semiCount = premiereLigne.components(separatedBy: ";").count
        // Ne compter que les vraies virgules séparateurs (pas les virgules décimales entre chiffres)
        func countRealCommas(_ line: String) -> Int {
            let chars = Array(line)
            var count = 0
            for (i, c) in chars.enumerated() where c == "," {
                let prevIsDigit = i > 0 && chars[i-1].isNumber
                let nextIsDigit = i < chars.count - 1 && chars[i+1].isNumber
                if !(prevIsDigit && nextIsDigit) {
                    count += 1
                }
            }
            return count + 1 // +1 pour le nombre de colonnes
        }
        let commaCount = countRealCommas(premiereLigne)
        // Vérifier aussi sur les lignes de données si l'en-tête est court
        let dataTabCount = lignes.count > 1 ? lignes[1].components(separatedBy: "\t").count : 1
        let effectiveTabCount = max(tabCount, dataTabCount)
        // Compter les colonnes si on sépare par 2+ espaces consécutifs
        let multiSpaceRegex = try? NSRegularExpression(pattern: "\\s{2,}")
        let multiSpaceCount = (multiSpaceRegex?.numberOfMatches(in: premiereLigne, range: NSRange(premiereLigne.startIndex..., in: premiereLigne)) ?? 0) + 1
        let dataMultiSpaceCount: Int
        if lignes.count > 1 {
            dataMultiSpaceCount = (multiSpaceRegex?.numberOfMatches(in: lignes[1], range: NSRange(lignes[1].startIndex..., in: lignes[1])) ?? 0) + 1
        } else {
            dataMultiSpaceCount = 1
        }
        let effectiveMultiSpaceCount = max(multiSpaceCount, dataMultiSpaceCount)

        if effectiveTabCount > 1 && effectiveTabCount >= semiCount && effectiveTabCount >= commaCount && effectiveTabCount >= effectiveMultiSpaceCount {
            sep = "\t"
        } else if effectiveMultiSpaceCount >= 3 && effectiveMultiSpaceCount >= semiCount && effectiveMultiSpaceCount >= commaCount {
            sep = "  " // placeholder, will use regex split below
        } else if semiCount >= commaCount {
            sep = ";"
        } else {
            sep = ","
        }

        // Fonction de découpe d'une ligne selon le séparateur
        func splitLine(_ line: String) -> [String] {
            if sep == "  " {
                // Séparer par 2+ espaces consécutifs
                let parts = line.components(separatedBy: "  ").flatMap { $0.components(separatedBy: "\t") }
                return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                return line.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        // Parser l'en-tête pour identifier les colonnes
        let headersRaw = splitLine(lignes[0])
        let headers = headersRaw.map { $0.lowercased() }

        // Mapping flexible des noms de colonnes
        let colClient = headers.firstIndex(where: { ["client", "nom complet", "nom_complet"].contains($0) })
        let colPrenom = headers.firstIndex(where: { ["prénom", "prenom", "firstname"].contains($0) })
        let colNom = headers.firstIndex(where: { $0 == "nom" || $0 == "lastname" || $0 == "name" })
        let colTel = headers.firstIndex(where: { ["téléphone", "telephone", "tel", "tél", "phone", "mobile"].contains($0) })
        var colVariante = headers.firstIndex(where: { ["variante", "produit", "product", "article", "variant"].contains($0) })
        var colTaille = headers.firstIndex(where: { ["taille", "size", "pointure"].contains($0) })
        let colCouleur = headers.firstIndex(where: { ["couleur", "color", "colour", "coloris"].contains($0) })
        let colQuantite = headers.firstIndex(where: { ["quantité", "quantite", "qté", "qte", "qty", "quantity", "nb"].contains($0) })
        let colCategorie = headers.firstIndex(where: { ["catégorie", "categorie", "category", "cat", "groupe", "group"].contains($0) })
        var colPrix = headers.firstIndex(where: { h in
            h.contains("prix") || h.contains("price") || h.contains("tarif") || h == "pu" || h == "p.u." || h == "pu ht" || h == "unit price"
        })
        let colTotal = headers.firstIndex(where: { h in
            h.contains("total") || h.contains("montant") || h.contains("amount")
        })

        // Vérifier si la première ligne est un vrai en-tête ou déjà des données
        let toutesColonnesReconnues = [colClient, colPrenom, colNom, colTel, colVariante, colTaille, colCouleur, colQuantite, colCategorie, colPrix, colTotal]
        let aucunHeaderReconnu = toutesColonnesReconnues.allSatisfy { $0 == nil }

        // Compter combien de colonnes utiles sont reconnues par header
        let nbColsStructurees = [colClient, colPrenom, colNom, colTel, colTaille, colCouleur, colQuantite, colCategorie, colPrix, colTotal].compactMap({ $0 }).count

        // ── Classificateur de contenu de cellule ──
        // 0 = texte, 1 = prix, 2 = taille
        func classifyCell(_ s: String) -> Int {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
            let sansMon = t.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
            if sansMon.range(of: #"^\d+[.,]\d{1,2}$"#, options: .regularExpression) != nil { return 1 }
            if t.range(of: #"\d+[.,]?\d*\s*(l|cl|ml|kg|g|oz)"#, options: [.regularExpression, .caseInsensitive]) != nil { return 2 }
            let low = t.lowercased()
            if ["xxs","xs","s","m","l","xl","xxl","xxxl","2xl","3xl"].contains(low) { return 2 }
            return 0
        }

        // ── MODE SANS EN-TÊTE : auto-détection de la structure ──
        if aucunHeaderReconnu {
            // Si on a un vrai séparateur (pas des espaces), essayer la détection structurée
            if sep != "  " {
                let allParts = lignes.map { splitLine($0) }
                let maxCols = allParts.map(\.count).max() ?? 0

                if maxCols >= 2 {
                    // Classifier chaque cellule
                    let allTypes = allParts.map { $0.map { classifyCell($0) } }

                    // Vérifier si TRANSPOSÉ : chaque ligne a des cellules du même type
                    let rowHomogeneous = allTypes.allSatisfy { row in
                        guard let first = row.first else { return true }
                        return row.allSatisfy { $0 == first }
                    }
                    let rowTypes = allTypes.compactMap(\.first)
                    let hasTexte = rowTypes.contains(0)

                    if rowHomogeneous && hasTexte && lignes.count >= 2 {
                        // TRANSPOSÉ : lignes = attributs, colonnes = produits
                        let numProducts = allParts.map(\.count).min() ?? 0
                        var rowVariante: Int? = nil, rowTaille: Int? = nil, rowPrix: Int? = nil
                        for (i, row) in allTypes.enumerated() {
                            if let first = row.first {
                                switch first {
                                case 0: if rowVariante == nil { rowVariante = i }
                                case 1: if rowPrix == nil { rowPrix = i }
                                case 2: if rowTaille == nil { rowTaille = i }
                                default: break
                                }
                            }
                        }

                        for col in 0..<numProducts {
                            let nom = rowVariante != nil && col < allParts[rowVariante!].count
                                ? allParts[rowVariante!][col].trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
                                : ""
                            let taille = rowTaille != nil && col < allParts[rowTaille!].count
                                ? allParts[rowTaille!][col].trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
                                : ""
                            let prixRaw = rowPrix != nil && col < allParts[rowPrix!].count ? allParts[rowPrix!][col] : ""
                            let prix = Double(prixRaw.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)) ?? 0

                            guard !nom.isEmpty else { continue }

                            if !variantes.contains(where: { $0.nom.localizedCaseInsensitiveCompare(nom) == .orderedSame }) {
                                variantes.append(Variante(nom: nom, prix: taille.isEmpty ? prix : 0))
                                result.variantesCrees += 1
                            }
                            if let idx = variantes.firstIndex(where: { $0.nom.localizedCaseInsensitiveCompare(nom) == .orderedSame }) {
                                if !taille.isEmpty {
                                    if !variantes[idx].tailles.contains(where: { $0.localizedCaseInsensitiveCompare(taille) == .orderedSame }) {
                                        variantes[idx].tailles.append(taille)
                                    }
                                    if prix > 0 {
                                        variantes[idx].prixTailles[taille] = prix
                                        result.prixImportes += 1
                                    }
                                } else if prix > 0 && variantes[idx].prix == 0 {
                                    variantes[idx].prix = prix
                                    result.prixImportes += 1
                                }
                            }
                        }

                        if result.variantesCrees > 0 || result.prixImportes > 0 {
                            save()
                        }
                        return result

                    } else if !rowHomogeneous && maxCols >= 2 {
                        // NORMAL sans en-tête : chaque ligne = un produit, colonnes = attributs
                        // Auto-détecter les rôles des colonnes depuis la première ligne
                        var autoColV: Int? = nil, autoColT: Int? = nil, autoColP: Int? = nil
                        if let firstRow = allTypes.first {
                            for (i, t) in firstRow.enumerated() {
                                switch t {
                                case 0: if autoColV == nil { autoColV = i }
                                case 2: if autoColT == nil { autoColT = i }
                                case 1: if autoColP == nil { autoColP = i }
                                default: break
                                }
                            }
                        }
                        if autoColV != nil {
                            return parseCampagneCSV(lignes: lignes, sep: sep, headers: [], colVariante: autoColV, colTaille: autoColT, colCouleur: nil, colPrix: autoColP, colTotal: nil, dataStartIndex: 0, lineSplitter: splitLine)
                        }
                    }
                }
            }

            // Fallback : parsing sémantique (texte brut sans séparateur clair)
            return parseLinesBySemantic(lignes: lignes)
        }
        if colVariante != nil && nbColsStructurees == 0 {
            // On a juste "Variante" comme header → parser le reste sémantiquement
            let dataLines = Array(lignes.dropFirst())
            return parseLinesBySemantic(lignes: dataLines)
        }

        // Index de début des données : 1 (on a un header reconnu avec structure)
        let dataStartIndex = 1

        // Auto-détection taille/prix par contenu quand variante trouvée par header mais pas taille/prix
        if colVariante != nil && colTaille == nil && colPrix == nil {
            let sampleParts = splitLine(lignes.count > 1 ? lignes[1] : lignes[0])
            let varCol = colVariante ?? 0
            // Chercher prix : dernière colonne purement numérique
            for idx in stride(from: sampleParts.count - 1, through: 0, by: -1) where idx != varCol {
                let val = sampleParts[idx]
                let sansMonnaie = val.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "€", with: "")
                if sansMonnaie.range(of: #"[a-zA-Z]"#, options: .regularExpression) == nil {
                    let norm = val.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
                    if let _ = Double(norm), !norm.isEmpty {
                        colPrix = idx
                        break
                    }
                }
            }
            // Chercher taille : colonne avec volume/unité pattern
            for (idx, val) in sampleParts.enumerated() where idx != varCol && idx != colPrix {
                let low = val.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if low.range(of: #"\d+[.,]?\d*\s*(l|cl|ml|kg|g|oz)"#, options: .regularExpression) != nil ||
                   ["xs", "s", "m", "l", "xl", "xxl", "xxxl", "2xl", "3xl"].contains(low) ||
                   low.range(of: #"^\d{2}$"#, options: .regularExpression) != nil {
                    colTaille = idx
                    break
                }
            }
        }

        // Dernier recours : si aucune colonne variante, col 0
        if colVariante == nil && colClient == nil && colPrenom == nil && colNom == nil {
            colVariante = 0
        }

        // Mode campagne seule (pas de colonne client) ou mode commandes (avec clients)
        let aClient = colClient != nil || colPrenom != nil || colNom != nil

        // Sans client mais avec variante → importer uniquement les variantes/tailles/prix
        if !aClient {
            guard colVariante != nil else {
                result.erreurs.append("Colonnes requises manquantes : « Client » ou « Nom »/« Prénom », ou au minimum « Variante ». Colonnes détectées : \(headers.joined(separator: ", "))")
                return result
            }
            return parseCampagneCSV(lignes: lignes, sep: sep, headers: headers, colVariante: colVariante, colTaille: colTaille, colCouleur: colCouleur, colPrix: colPrix, colTotal: colTotal, dataStartIndex: dataStartIndex, lineSplitter: splitLine)
        }

        // Regrouper les lignes par clé client (nom complet normalisé)
        struct LigneImport {
            var prenom: String
            var nom: String
            var telephone: String
            var variante: String
            var taille: String
            var couleur: String
            var quantite: Double
            var categorie: String
            var prix: Double?
        }

        var lignesImport: [LigneImport] = []

        for i in dataStartIndex..<lignes.count {
            let parts = splitLine(lignes[i])
            guard parts.count >= 2 else { continue }

            func val(_ index: Int?) -> String {
                guard let idx = index, idx < parts.count else { return "" }
                return parts[idx]
            }

            let importPrenom: String
            let importNom: String

            if let colC = colClient {
                // Colonne "Client" ou "Nom complet" → séparer au premier espace
                let full = val(colC)
                let composants = full.split(separator: " ", maxSplits: 1).map(String.init)
                importPrenom = composants.first ?? full
                importNom = composants.count > 1 ? composants[1] : ""
            } else {
                importPrenom = val(colPrenom)
                importNom = val(colNom)
            }

            let nomComplet = [importPrenom, importNom].filter { !$0.isEmpty }.joined(separator: " ")
            guard !nomComplet.isEmpty else { continue }

            // Quantité : accepter virgule comme séparateur décimal
            let qteStr = val(colQuantite).replacingOccurrences(of: ",", with: ".")
            let qte = Double(qteStr) ?? (colQuantite == nil ? 1 : 0)
            guard qte > 0 else { continue }

            // Prix : accepter virgule comme séparateur décimal, ignorer symboles monétaires
            let prixVal: Double?
            let prixRaw = val(colPrix)
            let totalRaw = val(colTotal)
            if !prixRaw.isEmpty {
                let prixClean = prixRaw.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
                prixVal = Double(prixClean)
            } else if !totalRaw.isEmpty, qte > 0 {
                // Pas de colonne prix mais colonne total : calculer le prix unitaire
                let totalClean = totalRaw.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
                if let totalNum = Double(totalClean) {
                    prixVal = totalNum / qte
                } else {
                    prixVal = nil
                }
            } else {
                prixVal = nil
            }

            lignesImport.append(LigneImport(
                prenom: importPrenom,
                nom: importNom,
                telephone: val(colTel),
                variante: val(colVariante),
                taille: val(colTaille),
                couleur: val(colCouleur),
                quantite: qte,
                categorie: val(colCategorie),
                prix: prixVal
            ))
        }

        guard !lignesImport.isEmpty else {
            result.erreurs.append("Aucune ligne de commande valide trouvée.")
            return result
        }

        // Créer les variantes manquantes et affecter les prix
        for ligne in lignesImport where !ligne.variante.isEmpty {
            if !variantes.contains(where: { $0.nom.localizedCaseInsensitiveCompare(ligne.variante) == .orderedSame }) {
                variantes.append(Variante(nom: ligne.variante, prix: ligne.taille.isEmpty ? (ligne.prix ?? 0) : 0))
                result.variantesCrees += 1
            }
            if let idx = variantes.firstIndex(where: { $0.nom.localizedCaseInsensitiveCompare(ligne.variante) == .orderedSame }) {
                // Prix de base uniquement si pas de taille sur cette ligne
                if let p = ligne.prix, p > 0, ligne.taille.isEmpty, variantes[idx].prix == 0 {
                    variantes[idx].prix = p
                }
                // Ajouter taille si nouvelle
                if !ligne.taille.isEmpty,
                   !variantes[idx].tailles.contains(where: { $0.localizedCaseInsensitiveCompare(ligne.taille) == .orderedSame }) {
                    variantes[idx].tailles.append(ligne.taille)
                }
                // Ajouter couleur si nouvelle
                if !ligne.couleur.isEmpty,
                   !variantes[idx].couleurs.contains(where: { $0.localizedCaseInsensitiveCompare(ligne.couleur) == .orderedSame }) {
                    variantes[idx].couleurs.append(ligne.couleur)
                }
                // Toujours stocker le prix par taille quand une taille est présente
                if let p = ligne.prix, p > 0, !ligne.taille.isEmpty {
                    variantes[idx].prixTailles[ligne.taille] = p
                    result.prixImportes += 1
                } else if let p = ligne.prix, p > 0, ligne.taille.isEmpty {
                    result.prixImportes += 1
                }
            }
        }

        // Regrouper par client (nom complet normalisé)
        struct CleClient: Hashable {
            let nomComplet: String
        }

        var clientsMap: [CleClient: [LigneImport]] = [:]
        var clientOrder: [CleClient] = []
        for ligne in lignesImport {
            let cle = CleClient(nomComplet: [ligne.prenom, ligne.nom].filter { !$0.isEmpty }.joined(separator: " ").lowercased())
            if clientsMap[cle] == nil {
                clientOrder.append(cle)
            }
            clientsMap[cle, default: []].append(ligne)
        }

        // Créer ou compléter les commandes
        for cle in clientOrder {
            guard let lignesClient = clientsMap[cle] else { continue }
            guard let premiere = lignesClient.first else { continue }

            let nomComplet = [premiere.prenom, premiere.nom].filter { !$0.isEmpty }.joined(separator: " ")

            // Chercher une commande existante pour ce client
            let existingIndex = orders.firstIndex(where: { $0.nomComplet.localizedCaseInsensitiveCompare(nomComplet) == .orderedSame })

            // Résoudre la catégorie
            var catID: UUID? = nil
            let catNom = premiere.categorie
            if !catNom.isEmpty {
                if let existing = categories.first(where: { $0.nom.localizedCaseInsensitiveCompare(catNom) == .orderedSame }) {
                    catID = existing.id
                } else {
                    let nouvelle = CategorieClient(nom: catNom)
                    categories.append(nouvelle)
                    catID = nouvelle.id
                }
            }

            // Construire les lignes de commande
            var lignesCommande: [LigneCommande] = []
            for l in lignesClient {
                // Résoudre le nom exact de la variante (casse du référentiel)
                let nomVariante = variantes.first(where: { $0.nom.localizedCaseInsensitiveCompare(l.variante) == .orderedSame })?.nom ?? l.variante
                let taille = l.taille.isEmpty ? nil : l.taille
                let couleur = l.couleur.isEmpty ? nil : l.couleur

                lignesCommande.append(LigneCommande(
                    variante: nomVariante,
                    taille: taille,
                    couleur: couleur,
                    quantite: l.quantite
                ))
                result.lignesAjoutees += 1
            }

            if let idx = existingIndex {
                // Ajouter les lignes à la commande existante
                orders[idx].lignes.append(contentsOf: lignesCommande)
                if orders[idx].telephone.isEmpty && !premiere.telephone.isEmpty {
                    orders[idx].telephone = premiere.telephone
                }
                if catID != nil && orders[idx].categorieID == nil {
                    orders[idx].categorieID = catID
                }
            } else {
                // Nouvelle commande
                var order = Order()
                order.prenom = premiere.prenom
                order.nom = premiere.nom
                order.telephone = premiere.telephone
                order.categorieID = catID
                order.lignes = lignesCommande
                orders.append(order)
                result.commandesCreees += 1
            }
        }

        if result.lignesAjoutees > 0 { save() }
        return result
    }

    // MARK: - Import sémantique (sans en-tête)

    /// Parse les lignes par extraction regex : prix = dernier nombre, taille = volume/unité, reste = variante.
    /// Utilisé quand aucun en-tête CSV n'est reconnu (fichier texte brut avec espaces, tabs, etc.).
    private func parseLinesBySemantic(lignes: [String]) -> ImportCommandesResult {
        var result = ImportCommandesResult()

        // Regex prix : nombre (avec virgule ou point décimal) suivi optionnellement de $, €, ou en fin de ligne
        let prixRegex = try! NSRegularExpression(pattern: #"(\d+[.,]\d{1,2})\s*[$€]?\s*$"#)

        // Regex taille/volume : nombre + unité
        let tailleRegex = try! NSRegularExpression(pattern: #"(\d+[.,]?\d*)\s*(l|cl|ml|kg|g|oz)\.?"#, options: .caseInsensitive)

        // Regex tailles textiles
        let tailleTextileRegex = try! NSRegularExpression(pattern: #"\b(XXS|XS|XXL|XXXL|XL|S|M|L|2XL|3XL|\d{2})\b"#, options: .caseInsensitive)

        struct LigneParsee {
            var variante: String
            var taille: String
            var prix: Double?
        }

        var parsed: [LigneParsee] = []

        for ligne in lignes {
            var remaining = ligne.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remaining.isEmpty else { continue }

            // 1. Extraire le prix (dernier nombre de la ligne)
            var prix: Double? = nil
            let range = NSRange(remaining.startIndex..., in: remaining)
            if let match = prixRegex.firstMatch(in: remaining, range: range),
               let prixRange = Range(match.range(at: 1), in: remaining) {
                let prixStr = String(remaining[prixRange]).replacingOccurrences(of: ",", with: ".")
                prix = Double(prixStr)
                let fullMatchRange = Range(match.range, in: remaining)!
                remaining = String(remaining[remaining.startIndex..<fullMatchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !remaining.isEmpty else { continue }

            // 2. Extraire la taille/volume
            var taille = ""
            let remRange = NSRange(remaining.startIndex..., in: remaining)
            if let match = tailleRegex.firstMatch(in: remaining, range: remRange),
               let tailleRange = Range(match.range, in: remaining) {
                taille = String(remaining[tailleRange]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                remaining = remaining.replacingCharacters(in: tailleRange, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: .punctuationCharacters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let match = tailleTextileRegex.firstMatch(in: remaining, range: remRange),
                      let tailleRange = Range(match.range, in: remaining) {
                let candidate = String(remaining[tailleRange])
                if remaining.count > candidate.count + 2 {
                    taille = candidate
                    remaining = remaining.replacingCharacters(in: tailleRange, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: .punctuationCharacters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // 3. Le reste = nom de la variante
            let nomVariante = remaining.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nomVariante.isEmpty else { continue }

            parsed.append(LigneParsee(variante: nomVariante, taille: taille, prix: prix))
        }

        // Créer/mettre à jour les variantes
        for p in parsed {
            if !variantes.contains(where: { $0.nom.localizedCaseInsensitiveCompare(p.variante) == .orderedSame }) {
                variantes.append(Variante(nom: p.variante, prix: p.taille.isEmpty ? (p.prix ?? 0) : 0))
                result.variantesCrees += 1
            }

            if let idx = variantes.firstIndex(where: { $0.nom.localizedCaseInsensitiveCompare(p.variante) == .orderedSame }) {
                // Prix de base uniquement si pas de taille
                if let pr = p.prix, pr > 0, p.taille.isEmpty, variantes[idx].prix == 0 {
                    variantes[idx].prix = pr
                }
                // Taille
                if !p.taille.isEmpty, !variantes[idx].tailles.contains(where: { $0.localizedCaseInsensitiveCompare(p.taille) == .orderedSame }) {
                    variantes[idx].tailles.append(p.taille)
                }
                // Prix par taille
                if let pr = p.prix, pr > 0, !p.taille.isEmpty {
                    variantes[idx].prixTailles[p.taille] = pr
                    result.prixImportes += 1
                } else if let pr = p.prix, pr > 0, p.taille.isEmpty {
                    result.prixImportes += 1
                }
            }
        }

        guard result.variantesCrees > 0 || result.prixImportes > 0 else {
            result.erreurs.append("Aucune variante trouvée dans le fichier.")
            return result
        }

        save()
        return result
    }

    /// Import CSV campagne seule (variantes/tailles/couleurs/prix, sans clients).
    private func parseCampagneCSV(lignes: [String], sep: String, headers: [String], colVariante: Int?, colTaille: Int?, colCouleur: Int?, colPrix: Int?, colTotal: Int?, dataStartIndex: Int = 1, lineSplitter: ((String) -> [String])? = nil) -> ImportCommandesResult {
        var result = ImportCommandesResult()

        let splitFn: (String) -> [String] = lineSplitter ?? { line in
            line.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
        }

        for i in dataStartIndex..<lignes.count {
            let parts = splitFn(lignes[i])
            guard parts.count >= 1 else { continue }

            func val(_ index: Int?) -> String {
                guard let idx = index, idx < parts.count else { return "" }
                return parts[idx]
            }

            let nomVariante = val(colVariante)
            guard !nomVariante.isEmpty else { continue }

            let taille = val(colTaille)
            let couleur = val(colCouleur)

            // Prix
            let prixVal: Double?
            let prixRaw = val(colPrix)
            let totalRaw = val(colTotal)
            if !prixRaw.isEmpty {
                let prixClean = prixRaw.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
                prixVal = Double(prixClean)
            } else if !totalRaw.isEmpty {
                let totalClean = totalRaw.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
                prixVal = Double(totalClean)
            } else {
                prixVal = nil
            }

            // Créer ou mettre à jour la variante
            if !variantes.contains(where: { $0.nom.localizedCaseInsensitiveCompare(nomVariante) == .orderedSame }) {
                variantes.append(Variante(nom: nomVariante, prix: taille.isEmpty ? (prixVal ?? 0) : 0))
                result.variantesCrees += 1
            }

            if let idx = variantes.firstIndex(where: { $0.nom.localizedCaseInsensitiveCompare(nomVariante) == .orderedSame }) {
                // Prix de base uniquement si pas de taille
                if let p = prixVal, p > 0, taille.isEmpty, variantes[idx].prix == 0 {
                    variantes[idx].prix = p
                }
                // Taille
                if !taille.isEmpty, !variantes[idx].tailles.contains(where: { $0.localizedCaseInsensitiveCompare(taille) == .orderedSame }) {
                    variantes[idx].tailles.append(taille)
                }
                // Couleur
                if !couleur.isEmpty, !variantes[idx].couleurs.contains(where: { $0.localizedCaseInsensitiveCompare(couleur) == .orderedSame }) {
                    variantes[idx].couleurs.append(couleur)
                }
                // Prix par taille
                if let p = prixVal, p > 0, !taille.isEmpty {
                    variantes[idx].prixTailles[taille] = p
                    result.prixImportes += 1
                } else if let p = prixVal, p > 0, taille.isEmpty {
                    result.prixImportes += 1
                }
            }
        }

        guard result.variantesCrees > 0 || result.prixImportes > 0 else {
            result.erreurs.append("Aucune variante trouvée dans le fichier.")
            return result
        }

        save()
        return result
    }

    // MARK: - Import IA (produits structurés)

    /// Crée/met à jour les variantes à partir de la liste de produits extraits par l'IA.
    /// Route directement vers les variantes, sans passer par le parser CSV (qui cherche des commandes clients).
    func appliquerProduitsIA(_ produits: [ProduitIA]) -> ImportCommandesResult {
        var result = ImportCommandesResult()

        for p in produits {
            let nom = p.nom.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nom.isEmpty else { continue }

            let taille = p.taille.trimmingCharacters(in: .whitespacesAndNewlines)
            let couleur = p.couleur.trimmingCharacters(in: .whitespacesAndNewlines)

            // Créer la variante si elle n'existe pas
            if !variantes.contains(where: { $0.nom.localizedCaseInsensitiveCompare(nom) == .orderedSame }) {
                variantes.append(Variante(nom: nom, prix: taille.isEmpty ? p.prix : 0))
                result.variantesCrees += 1
            }

            // Mettre à jour taille, couleur et prix
            if let idx = variantes.firstIndex(where: { $0.nom.localizedCaseInsensitiveCompare(nom) == .orderedSame }) {
                // Ajouter la couleur (= contenant : Bouteille, Bidon, Bag in Box…)
                if !couleur.isEmpty {
                    if !variantes[idx].couleurs.contains(where: { $0.localizedCaseInsensitiveCompare(couleur) == .orderedSame }) {
                        variantes[idx].couleurs.append(couleur)
                    }
                }

                if taille.isEmpty {
                    // Prix de base (sans taille)
                    if p.prix > 0 && variantes[idx].prix == 0 {
                        variantes[idx].prix = p.prix
                        result.prixImportes += 1
                    }
                } else {
                    // Ajouter la taille (= volume : 25cl, 50cl, 100cl…)
                    if !variantes[idx].tailles.contains(where: { $0.localizedCaseInsensitiveCompare(taille) == .orderedSame }) {
                        variantes[idx].tailles.append(taille)
                    }
                    // Prix par taille
                    if p.prix > 0 {
                        variantes[idx].prixTailles[taille] = p.prix
                        result.prixImportes += 1
                    }
                }

                // Prix par combinaison taille+couleur ou par couleur seule
                if !couleur.isEmpty && p.prix > 0 {
                    if !taille.isEmpty {
                        let cle = Variante.cleCombinaison(taille, couleur)
                        variantes[idx].prixCombinaisons[cle] = p.prix
                    }
                    variantes[idx].prixCouleurs[couleur] = p.prix
                }
            }
        }

        if result.variantesCrees > 0 || result.prixImportes > 0 {
            save()
        }
        return result
    }

    // MARK: - Import commandes depuis image/PDF (OCR)

    /// Importe des commandes depuis une image (photo ou capture) via reconnaissance de texte (OCR).
    /// Le traitement est effectué en arrière-plan ; le résultat est renvoyé sur le main thread.
    func importerCommandesDepuisImage(_ image: UIImage, completion: @escaping (ImportCommandesResult) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(ImportCommandesResult(erreurs: ["Image invalide."]))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let observations = self.ocrCGImage(cgImage)
            let csvText = self.reconstructTableFromOCR(observations)
            if csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    completion(ImportCommandesResult(erreurs: ["Aucun texte reconnu dans l'image."]))
                }
                return
            }
            DispatchQueue.main.async {
                // Si IA configurée → priorité IA
                if AITriageService.shared.estConfigure {
                    AITriageService.shared.trierTexte(csvText) { produits in
                        let diag = AITriageService.shared.dernierDiagnostic
                        if let produits = produits {
                            var resultIA = self.appliquerProduitsIA(produits)
                            resultIA.diagnosticIA = diag
                            if resultIA.variantesCrees > 0 || resultIA.prixImportes > 0 {
                                completion(resultIA)
                                return
                            }
                        }
                        // Fallback : parsing classique
                        var result = self.parseCommandesCSV(csvText)
                        result.diagnosticIA = "Fallback classique. IA: \(diag)"
                        completion(result)
                    }
                } else {
                    let result = self.parseCommandesCSV(csvText)
                    completion(result)
                }
            }
        }
    }

    /// Importe des commandes depuis un fichier PDF ou image. Tente d'abord l'extraction de texte directe,
    /// puis recourt à l'OCR si nécessaire.
    func importerCommandesDepuisPDFOuImage(url: URL, completion: @escaping (ImportCommandesResult) -> Void) {
        // Vérifier si c'est une image
        if let image = UIImage(contentsOfFile: url.path) {
            importerCommandesDepuisImage(image, completion: completion)
            return
        }

        // Tenter d'ouvrir comme PDF
        guard let document = PDFDocument(url: url) else {
            completion(ImportCommandesResult(erreurs: ["Impossible d'ouvrir le fichier comme PDF ou image."]))
            return
        }

        // Tenter d'abord l'extraction de texte directe (PDF non scanné)
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        if AITriageService.shared.estConfigure {
            print("🟢 [IMPORT PDF] IA configurée, texte brut: \(fullText.count) car.")
            AITriageService.shared.logDebug("=== TEXTE BRUT PDF page.string (\(fullText.count) car.) ===\n\(fullText.prefix(5000))\n=== FIN TEXTE BRUT ===")

            // 1) PRIORITAIRE : envoyer le texte brut directement à l'IA (meilleure compréhension)
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🟢 [IMPORT PDF] Envoi du texte brut à l'IA...")
                AITriageService.shared.trierTexte(fullText) { produits in
                    if let produits = produits {
                        print("🟢 [IMPORT PDF] IA texte: \(produits.count) produits")
                        let diag = AITriageService.shared.dernierDiagnostic
                        var resultIA = self.appliquerProduitsIA(produits)
                        resultIA.diagnosticIA = diag
                        print("🟢 [IMPORT PDF] appliquerProduitsIA: \(resultIA.variantesCrees) variantes, \(resultIA.prixImportes) prix")
                        DispatchQueue.main.async { completion(resultIA) }
                        return
                    }
                    print("🔴 [IMPORT PDF] IA texte a échoué, fallback parsing direct...")

                    // 2) Fallback : parsing direct (regex, gratuit, déterministe)
                    if let produitsDirect = AITriageService.shared.parserDirectement(fullText) {
                        print("🟡 [IMPORT PDF] Parsing direct: \(produitsDirect.count) produits")
                        let diag = AITriageService.shared.dernierDiagnostic
                        var resultIA = self.appliquerProduitsIA(produitsDirect)
                        resultIA.diagnosticIA = diag
                        DispatchQueue.main.async { completion(resultIA) }
                        return
                    }
                    print("🔴 [IMPORT PDF] Parsing direct a échoué, fallback OCR...")

                    // 3) Dernier recours : OCR + IA (pour PDF scannés)
                    self.importerPDFParOCR(document: document, completion: completion)
                }
                return
            }
            print("🔴 [IMPORT PDF] Texte brut vide, fallback OCR...")
            // OCR + IA (pas de texte intégré → PDF scanné)
            importerPDFParOCR(document: document, completion: completion)
            return
        }
        print("🔴 [IMPORT PDF] IA non configurée, parsing CSV classique")

        // Sans IA : parsing classique du texte direct
        if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result = parseCommandesCSV(fullText)
            if result.lignesAjoutees > 0 || result.variantesCrees > 0 {
                DispatchQueue.main.async { completion(result) }
                return
            }
        }

        // Fallback : OCR sur chaque page rendue en image
        importerPDFParOCR(document: document, completion: completion)
    }

    /// Importe un PDF via OCR page par page, puis tente le triage IA si disponible.
    private func importerPDFParOCR(document: PDFDocument, completion: @escaping (ImportCommandesResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var allCSVLines: [String] = []
            var headerLine: String? = nil

            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0
                let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.cgContext.translateBy(x: 0, y: size.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }

                guard let cgImage = image.cgImage else { continue }
                let observations = self.ocrCGImage(cgImage)
                let pageCSV = self.reconstructTableFromOCR(observations)
                let pageLines = pageCSV.components(separatedBy: "\n").filter { !$0.isEmpty }

                // Sur les pages suivantes, ignorer l'en-tête s'il est répété
                if i == 0 {
                    allCSVLines.append(contentsOf: pageLines)
                    headerLine = pageLines.first?.lowercased()
                } else {
                    for line in pageLines {
                        if let h = headerLine, line.lowercased() == h { continue }
                        allCSVLines.append(line)
                    }
                }
            }

            let csvText = allCSVLines.joined(separator: "\n")
            if csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    completion(ImportCommandesResult(erreurs: ["Aucun texte reconnu dans le PDF."]))
                }
                return
            }

            DispatchQueue.main.async {
                // Si IA configurée → priorité IA
                if AITriageService.shared.estConfigure {
                    AITriageService.shared.trierTexte(csvText) { produits in
                        let diag = AITriageService.shared.dernierDiagnostic
                        if let produits = produits {
                            var resultIA = self.appliquerProduitsIA(produits)
                            resultIA.diagnosticIA = diag
                            if resultIA.variantesCrees > 0 || resultIA.prixImportes > 0 {
                                completion(resultIA)
                                return
                            }
                        }
                        // IA n'a rien donné → fallback parsing classique
                        var result = self.parseCommandesCSV(csvText)
                        result.diagnosticIA = "Fallback classique. IA: \(diag)"
                        if result.lignesAjoutees > 0 || result.variantesCrees > 0 {
                            completion(result)
                        } else {
                            completion(ImportCommandesResult(erreurs: ["Le PDF est trop complexe. Aucun produit reconnu."], diagnosticIA: "Echec total. IA: \(diag)"))
                        }
                    }
                } else {
                    let result = self.parseCommandesCSV(csvText)
                    completion(result)
                }
            }
        }
    }

    /// Effectue la reconnaissance de texte sur une image Core Graphics (synchrone, appeler depuis un thread d'arrière-plan).
    private func ocrCGImage(_ cgImage: CGImage) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results ?? []
    }

    /// Reconstruit un texte CSV à partir des observations OCR en analysant les positions spatiales.
    private func reconstructTableFromOCR(_ observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        struct TextBlock {
            let text: String
            let midX: CGFloat
            let midY: CGFloat  // 0 = top, 1 = bottom (inversé par rapport à Vision)
            let height: CGFloat
        }

        var blocks: [TextBlock] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let box = obs.boundingBox
            blocks.append(TextBlock(
                text: candidate.string,
                midX: box.midX,
                midY: 1 - box.midY,
                height: box.height
            ))
        }

        guard !blocks.isEmpty else { return "" }

        // Si la plupart des blocs contiennent déjà des séparateurs, ce sont des lignes complètes
        let separatorCount = blocks.filter { $0.text.contains(";") || $0.text.contains("\t") }.count
        if separatorCount > blocks.count / 2 {
            let sorted = blocks.sorted { $0.midY < $1.midY }
            return sorted.map { $0.text.replacingOccurrences(of: "\t", with: ";") }.joined(separator: "\n")
        }

        // Regrouper par ligne (proximité en Y)
        let sortedByY = blocks.sorted { $0.midY < $1.midY }
        let heights = blocks.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let threshold = medianHeight * 0.6

        var rows: [[TextBlock]] = []
        var currentRow: [TextBlock] = []
        var currentRowY: CGFloat = -1

        for block in sortedByY {
            if currentRowY < 0 || abs(block.midY - currentRowY) <= threshold {
                currentRow.append(block)
                currentRowY = currentRow.map(\.midY).reduce(0, +) / CGFloat(currentRow.count)
            } else {
                rows.append(currentRow.sorted { $0.midX < $1.midX })
                currentRow = [block]
                currentRowY = block.midY
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow.sorted { $0.midX < $1.midX })
        }

        // Convertir en CSV (colonnes séparées par ;)
        return rows.map { row in
            row.map(\.text).joined(separator: ";")
        }.joined(separator: "\n")
    }

    /// Importe une commande depuis les données encodées dans un deep link. Retourne le nom du client importé, ou nil en cas d'échec.
    func importerCommandeDepuisURL(_ url: URL) -> String? {
        guard url.scheme == "groop", url.host == "order" else { return nil }
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

        // Vérifier si un client avec ce téléphone ou ce nom existe déjà
        let tel = commande.p ?? ""
        let telNorm = normaliserTelephone(tel)
        let nomWeb = commande.n.lowercased().trimmingCharacters(in: .whitespaces)
        if let index = orders.firstIndex(where: {
            (!telNorm.isEmpty && normaliserTelephone($0.telephone) == telNorm) ||
            (!nomWeb.isEmpty && $0.nomComplet.lowercased().trimmingCharacters(in: .whitespaces) == nomWeb)
        }) {
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
            if orders[index].nomComplet.isEmpty {
                let composants = commande.n.split(separator: " ", maxSplits: 1).map(String.init)
                orders[index].prenom = composants.first ?? commande.n
                orders[index].nom = composants.count > 1 ? composants[1] : ""
            }
        } else {
            var order = Order()
            let composants = commande.n.split(separator: " ", maxSplits: 1).map(String.init)
            order.prenom = composants.first ?? commande.n
            order.nom = composants.count > 1 ? composants[1] : ""
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
