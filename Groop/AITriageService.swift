//
//  AITriageService.swift
//  Groop
//
//  Service de triage IA pour les PDFs complexes (catalogues, tarifs pro, etc.).
//  Utilise l'API OpenAI pour nettoyer le texte brut extrait des PDFs :
//  reconnaître les produits, ignorer titres/TVA/en-têtes.
//

import Foundation

/// Résultat structuré du triage IA : liste de produits extraits.
struct ProduitIA {
    var nom: String
    var taille: String   // volume/poids (25cl, 1L, 5kg…), vide si absent
    var couleur: String  // contenant/conditionnement (Bouteille, Bidon, Bag in Box…), vide si absent
    var prix: Double     // 0 si non trouvé
}

/// Service de triage IA qui nettoie le texte brut extrait des PDFs complexes
/// en identifiant les lignes produit et en éliminant le bruit (titres, TVA, etc.).
class AITriageService {

    static let shared = AITriageService()
    private init() {}

    /// Clé API OpenAI stockée dans UserDefaults
    var cleAPI: String {
        get { UserDefaults.standard.string(forKey: "openAICleAPI") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAICleAPI") }
    }

    /// Vérifie si le service IA est configuré (clé API présente)
    var estConfigure: Bool {
        !cleAPI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Triage principal

    /// Taille maximale d'un chunk envoyé à l'IA (en caractères).
    private let tailleMaxChunk = 3000

    /// Prompt système partagé entre tous les chunks.
    private var systemPrompt: String {
        [
            "Tu es un extracteur de catalogues produits professionnels.",
            "",
            "Tu recois le texte brut extrait d'un PDF de tarifs professionnel.",
            "Le texte peut etre dans 3 formats :",
            "- FORMAT A : colonnes separees par des points-virgules (;) sur chaque ligne.",
            "- FORMAT B : chaque champ sur sa propre ligne (nom, volume, conditionnement, prix, TVA sur des lignes separees).",
            "- FORMAT C : tous les champs sur une seule ligne separes par des espaces simples. Exemple : 'Intense AOP Bio 25cl Bouteille 7,85 € 5,50%'",
            "Les trois formats contiennent les memes informations.",
            "",
            "ATTENTION : les colonnes du PDF source varient. Voici des colonnes courantes :",
            "- Designation / Produit / Article",
            "- Contenance / Volume (25cl, 50cl, 75cl, 100cl, 3L...)",
            "- Conditionnement / Contenant (Bouteille, Bidon, Bag in Box, Cubi, Fontaine, Fut...)",
            "- Prix HT / Prix unitaire / P.U. HT (nombre comme 7,85 ou 12,40)",
            "- Prix TTC (souvent = Prix HT x (1 + TVA))",
            "- Taux TVA (5,50% ou 20,00% - CE N'EST PAS UN PRIX)",
            "- Code article / Reference (chiffres longs comme 3760xxx - A IGNORER)",
            "",
            "Ta mission : pour chaque ligne produit, extraire et SEPARER les informations dans ce format :",
            "NOM;VOLUME;CONTENANT;PRIX_HT",
            "",
            "Regles STRICTES :",
            "1. NOM = le nom commercial du produit uniquement.",
            "   Exemples : Intense AOP Bio, Fruite Vert, Cepes, Truffe, Vin Blanc, Vin Rose.",
            "   NE PAS inclure le volume, le contenant, le prix ou la TVA dans le nom.",
            "2. VOLUME = la contenance : 10cl, 15cl, 20cl, 25cl, 50cl, 75cl, 100cl, 3L, 5L, etc.",
            "   Si absent, laisser vide.",
            "3. CONTENANT = Bouteille, Bidon, Bag in Box, Cubi, Fontaine, Fut, Cannette, etc.",
            "   Si absent, laisser vide.",
            "4. PRIX_HT = le prix HT unitaire comme nombre decimal avec POINT. Ex: 7.85, 12.40",
            "   - Convertir la virgule decimale en point : 7,85 devient 7.85",
            "   - NE PAS confondre avec le taux de TVA (5,50% n'est PAS un prix).",
            "   - NE PAS prendre le prix TTC si le HT est disponible.",
            "   - Si aucun prix, mettre 0.",
            "5. Une ligne par combinaison produit + volume + contenant.",
            "   Le NOM doit etre identique entre les lignes du meme produit.",
            "6. IGNORER :",
            "   - Titres de sections en majuscules (ex: INTENSE AOP Provence, COFFRETS DECOUVERTE, VINS)",
            "   - En-tetes de colonnes (ex: Designation;Contenance;Conditionnement;Prix HT;TVA)",
            "   - Lignes avec uniquement un taux TVA (5,50%)",
            "   - Codes article longs (3760...), codes-barres",
            "   - Totaux, sous-totaux, remises, frais de port",
            "   - Mentions legales, adresses, telephones, numeros de page",
            "7. NE PAS mettre de ligne d'en-tete. NE PAS ajouter de texte explicatif.",
            "8. Si aucun produit, repondre : AUCUN_PRODUIT",
            "",
            "EXEMPLE 1 - FORMAT A (colonnes separees par ;) :",
            "INTENSE AOP Provence - CERTIFIEE BIO",
            "Intense AOP Bio;25cl;Bouteille;7,85;5,50%",
            "3760xxx;Intense AOP Bio;25cl;Bidon;7,40;5,50%",
            "Intense AOP Bio;50cl;Bouteille;12,85;5,50%",
            "FRUITE VERT",
            "Fruite Vert;25cl;Bouteille;6,50;5,50%",
            "",
            "EXEMPLE 2 - FORMAT B (un champ par ligne) :",
            "INTENSE AOP Provence – CERTIFIEE BIO",
            "Intense AOP Bio",
            "25cl",
            "Bouteille",
            "7,85 €",
            "5,50%",
            "Intense AOP Bio",
            "25cl",
            "Bidon",
            "7,40 €",
            "5,50%",
            "",
            "EXEMPLE 3 - FORMAT C (tout sur une ligne, espaces simples) :",
            "INTENSE AOP Provence – CERTIFIEE BIO",
            "Intense AOP Bio 25cl Bouteille 7,85 € 5,50%",
            "Intense AOP Bio 25cl Bidon 7,40 € 5,50%",
            "Intense AOP Bio 50cl Bouteille 12,85 € 5,50%",
            "FRUITE VERT",
            "Fruite Vert 25cl Bouteille 6,50 € 5,50%",
            "",
            "SORTIE ATTENDUE (identique pour les 3 formats) :",
            "Intense AOP Bio;25cl;Bouteille;7.85",
            "Intense AOP Bio;25cl;Bidon;7.40",
            "Intense AOP Bio;50cl;Bouteille;12.85",
            "Fruite Vert;25cl;Bouteille;6.50",
        ].joined(separator: "\n")
    }

    /// Envoie le texte brut extrait d'un PDF à l'IA pour triage.
    /// Si le texte dépasse `tailleMaxChunk`, il est découpé en morceaux envoyés séquentiellement,
    /// puis les résultats sont fusionnés.
    func trierTexte(_ texteBrut: String, completion: @escaping ([ProduitIA]?) -> Void) {
        guard estConfigure else {
            completion(nil)
            return
        }

        // Envoyer le texte BRUT à l'IA (elle comprend mieux le format compact que le prétraitement regex)
        // Normaliser seulement les caractères Unicode problématiques
        let texteNormalise = texteBrut
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{FF05}", with: "%")
            .replacingOccurrences(of: "\u{FFE0}", with: "€")
        logDebug("=== TEXTE BRUT NORMALISÉ (\(texteNormalise.count) car.) ===\n\(texteNormalise.prefix(2000))\n=== FIN TEXTE BRUT ===")

        let chunks = decouper(texte: texteNormalise, tailleMax: tailleMaxChunk)

        if chunks.count == 1 {
            // Cas simple : un seul chunk
            logDebug("=== TEXTE COURT (\(texteBrut.count) car.) → envoi direct ===")
            trierChunk(chunks[0], chunkIndex: 1, totalChunks: 1, completion: completion)
        } else {
            // Découpage en plusieurs chunks
            logDebug("=== DÉCOUPAGE EN \(chunks.count) CHUNKS (texte total: \(texteBrut.count) car.) ===")
            dernierDiagnostic = "Appel en cours (0/\(chunks.count) chunks)..."

            var tousLesProduits: [ProduitIA] = []
            var diagnostics: [String] = []

            func traiterChunk(index: Int) {
                guard index < chunks.count else {
                    // Tous les chunks traités → fusionner
                    if tousLesProduits.isEmpty {
                        self.dernierDiagnostic = "IA: aucun produit (\(chunks.count) chunks). " + diagnostics.joined(separator: " | ")
                        self.logDebug("=== RÉSULTAT FINAL : 0 produits sur \(chunks.count) chunks ===")
                        completion(nil)
                    } else {
                        let avecPrix = tousLesProduits.filter { $0.prix > 0 }.count
                        let avecTaille = tousLesProduits.filter { !$0.taille.isEmpty }.count
                        let avecCouleur = tousLesProduits.filter { !$0.couleur.isEmpty }.count
                        self.dernierDiagnostic = "IA: \(tousLesProduits.count) produits (\(chunks.count) chunks, \(avecPrix) prix, \(avecTaille) tailles, \(avecCouleur) contenants)"
                        self.logDebug("=== RÉSULTAT FINAL : \(tousLesProduits.count) produits sur \(chunks.count) chunks ===")
                        completion(tousLesProduits)
                    }
                    return
                }

                self.dernierDiagnostic = "Appel en cours (\(index + 1)/\(chunks.count) chunks)..."
                self.trierChunk(chunks[index], chunkIndex: index + 1, totalChunks: chunks.count) { produits in
                    if let produits = produits {
                        tousLesProduits.append(contentsOf: produits)
                        diagnostics.append("chunk\(index + 1): \(produits.count)")
                    } else {
                        diagnostics.append("chunk\(index + 1): 0")
                    }
                    traiterChunk(index: index + 1)
                }
            }

            traiterChunk(index: 0)
        }
    }

    // MARK: - Pré-traitement du texte

    /// Pré-traite le texte "un champ par ligne" (issu de page.string de PDFKit) en recombinant
    /// les champs en lignes `;`-séparées. Si le texte est déjà en format colonne, il est retourné tel quel.
    private func pretraiterTexte(_ texte: String) -> String {
        // Normaliser les caractères Unicode problématiques (non-breaking spaces, etc.)
        let normalise = texte
            .replacingOccurrences(of: "\u{00A0}", with: " ")  // non-breaking space
            .replacingOccurrences(of: "\u{202F}", with: " ")  // narrow non-breaking space
            .replacingOccurrences(of: "\u{2009}", with: " ")  // thin space
            .replacingOccurrences(of: "\u{FEFF}", with: "")   // BOM
            .replacingOccurrences(of: "€", with: "€")        // fullwidth euro sign

        var lignes = normalise.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Si déjà en format colonne (beaucoup de ;), ne pas toucher
        let avecSep = lignes.filter { $0.contains(";") }.count
        if avecSep > lignes.count / 3 { return texte }

        // === DÉTECTION DU FORMAT ===
        // Format A : tabulaire large (2+ espaces entre champs) — PyMuPDF sort=True
        // Format B : compact (1 espace entre champs, prix en fin de ligne) — PDFKit page.string sur iOS
        // Format C : un champ par ligne — PyMuPDF default

        // Compter les lignes qui contiennent un prix en milieu/fin de chaîne (pas en début)
        let prixEnFinDeLigne = lignes.filter { $0.range(of: #"\S\s+\d+[.,]\d{2}\s*€"#, options: .regularExpression) != nil }.count
        let avecEspacesMultiples = lignes.filter { $0.range(of: #"\S\s{2,}\S"#, options: .regularExpression) != nil }.count

        print("🔵 [PRETRAIT] \(lignes.count) lignes, \(avecEspacesMultiples) multi-espaces, \(prixEnFinDeLigne) prix en fin de ligne")

        if avecEspacesMultiples > lignes.count / 3 {
            // FORMAT A : tabulaire large → éclater sur 2+ espaces
            print("🔵 [PRETRAIT] Format TABULAIRE (multi-espaces) → éclatement")
            var eclatees: [String] = []
            for ligne in lignes {
                let parts = ligne.components(separatedBy: "  ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                eclatees.append(contentsOf: parts)
            }
            lignes = eclatees
            print("🔵 [PRETRAIT] Après éclatement: \(lignes.count) sous-lignes")

        } else if prixEnFinDeLigne > lignes.count / 5 {
            // FORMAT B : compact (PDFKit iOS) → construire le CSV directement et retourner
            print("🔵 [PRETRAIT] Format COMPACT (prix en fin de ligne) → extraction directe en CSV")
            var csvRows: [String] = []
            var dernierNomB = ""
            let regexPrix = try? NSRegularExpression(pattern: #"(\d+[.,]\d{2})\s*€"#)
            let regexTVA = try? NSRegularExpression(pattern: #"\d+[.,]?\d*\s*%"#)
            let regexTaille = try? NSRegularExpression(pattern: #"\b(\d+[.,]?\d*\s*(cl|l|g|kg|ml)\b|\d+\s*x\s*\d+\s*(cl|g|ml)|\d+g\s+net)"#, options: .caseInsensitive)
            let contenantsSet = ["bouteille", "bidon", "bag in box", "bocal", "pot",
                                  "cannette", "fut", "fût", "fontaine", "cubi",
                                  "6 bouteilles", "12 bouteilles"]
            let ignoreWords = Set(["référence", "format", "conditionnement", "prix ht", "tva", "commande",
                                    "nom", "prenom", "prénom", "mail", "numero mobile", "numéro mobile"])

            for ligne in lignes {
                let trimmed = ligne.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let tl = trimmed.lowercased()
                if tl.contains("@") || tl.contains("www.") || tl.contains("chemin de") ||
                   tl.contains("moulin bastide") || tl.contains("04 90") || ignoreWords.contains(tl) { continue }

                var reste = trimmed

                // 1) Retirer TVA en fin de ligne (ex: "5,50%")
                if let rx = regexTVA {
                    let range = NSRange(reste.startIndex..., in: reste)
                    if let match = rx.firstMatch(in: reste, range: range) {
                        let matchRange = Range(match.range, in: reste)!
                        reste = String(reste[reste.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                }

                // 2) Extraire le prix (premier trouvé)
                var prixStr = ""
                if let rx = regexPrix {
                    let range = NSRange(reste.startIndex..., in: reste)
                    if let match = rx.firstMatch(in: reste, range: range) {
                        let fullRange = Range(match.range, in: reste)!
                        let grpRange = Range(match.range(at: 1), in: reste)!
                        prixStr = String(reste[grpRange])
                        reste = (String(reste[reste.startIndex..<fullRange.lowerBound]) + " " +
                                 String(reste[fullRange.upperBound...])).trimmingCharacters(in: .whitespaces)
                    }
                }

                // Pas de prix → titre de section ou ligne à ignorer
                if prixStr.isEmpty {
                    // Titre en majuscules → mémoriser comme dernier nom
                    let lettres = reste.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                    let majuscules = lettres.filter { CharacterSet.uppercaseLetters.contains($0) }
                    if lettres.count > 3 && majuscules.count > lettres.count * 2 / 3 {
                        let titreNettoye = reste
                            .replacingOccurrences(of: #"\s*[–-]\s*CERTIFI.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                            .replacingOccurrences(of: #"\s*[–-]\s*par\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !titreNettoye.isEmpty { dernierNomB = titreNettoye.capitalized }
                    }
                    continue
                }

                // 3) Extraire le contenant
                var contenant = ""
                var resteLower = reste.lowercased()
                for c in contenantsSet.sorted(by: { $0.count > $1.count }) {
                    if let range = resteLower.range(of: c) {
                        contenant = String(reste[range])
                        reste = (String(reste[reste.startIndex..<range.lowerBound]) + " " +
                                 String(reste[range.upperBound...])).trimmingCharacters(in: .whitespaces)
                        resteLower = reste.lowercased()
                        break
                    }
                }

                // 4) Extraire la taille
                var tailleStr = ""
                if let rx = regexTaille {
                    let range = NSRange(reste.startIndex..., in: reste)
                    if let match = rx.firstMatch(in: reste, range: range) {
                        let matchRange = Range(match.range, in: reste)!
                        tailleStr = String(reste[matchRange])
                        reste = (String(reste[reste.startIndex..<matchRange.lowerBound]) + " " +
                                 String(reste[matchRange.upperBound...])).trimmingCharacters(in: .whitespaces)
                    }
                }

                // 5) Le reste = nom du produit
                let nom = reste.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

                let nomFinal = nom.isEmpty ? dernierNomB : nom
                if nomFinal.isEmpty { continue }
                if !nom.isEmpty { dernierNomB = nom }

                var parts = [nomFinal]
                if !tailleStr.isEmpty { parts.append(tailleStr) }
                if !contenant.isEmpty { parts.append(contenant) }
                parts.append(prixStr + " €")

                csvRows.append(parts.joined(separator: ";"))
            }
            print("🔵 [PRETRAIT] Format COMPACT: \(csvRows.count) lignes CSV générées")
            for (i, r) in csvRows.prefix(5).enumerated() { print("  B[\(i+1)] \(r)") }
            if csvRows.count > 10 { print("  ...") }
            for (i, r) in csvRows.suffix(3).enumerated() { print("  B[\(csvRows.count - 2 + i)] \(r)") }
            return csvRows.joined(separator: "\n")

        } else {
            print("🔵 [PRETRAIT] Format UN CHAMP PAR LIGNE")
        }

        // Patterns pour identifier le type de chaque ligne
        func estTaille(_ s: String) -> Bool {
            s.range(of: #"^\d+[.,]?\d*\s*(cl|l|g|kg|ml)\b"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            s.range(of: #"^\d+\s*x\s*\d+\s*(cl|g|ml)"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            s.range(of: #"^\d+g\s+net$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }

        let contenants = Set(["bouteille", "bidon", "bag in box", "bocal", "pot",
                               "cannette", "fut", "fût", "fontaine", "cubi",
                               "6 bouteilles", "12 bouteilles"])
        func estContenant(_ s: String) -> Bool { contenants.contains(s.lowercased()) }

        // Prix : "7,85 €", "7,85€", "7.85", "7,85" (avec ou sans €, espaces variés)
        func estPrix(_ s: String) -> Bool {
            s.range(of: #"^\d+[.,]\d{2}(\s|€|$)"#, options: .regularExpression) != nil
        }

        // TVA : "5,50%", "20,00%", "20%" (toujours avec %)
        func estTVA(_ s: String) -> Bool {
            s.range(of: #"^\d+[.,]?\d*\s*%"#, options: .regularExpression) != nil
        }

        func estTitre(_ s: String) -> Bool {
            // Lignes en majuscules (titres de section) — au moins 4 lettres, majorité uppercase
            let lettres = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let majuscules = lettres.filter { CharacterSet.uppercaseLetters.contains($0) }
            return lettres.count > 3 && majuscules.count > lettres.count * 2 / 3
        }

        func estIgnorer(_ s: String) -> Bool {
            let l = s.lowercased()
            return l.contains("@") || l.contains("www.") || l.contains("chemin de") ||
                   l.contains("moulin bastide") || l.contains("04 90") ||
                   ["référence", "format", "conditionnement", "prix ht", "tva", "commande",
                    "nom", "prenom", "prénom", "mail", "numero mobile", "numéro mobile"].contains(l)
        }

        var rows: [String] = []
        var current: [String] = []
        var dernierNom: String = ""  // dernier nom de produit reconnu (pour lignes sans nom)

        func flush() {
            guard !current.isEmpty else { return }
            let aUnPrix = current.contains { estPrix($0) }
            guard aUnPrix else {
                // Pas de prix → pas une ligne produit valide, on ignore
                current = []
                return
            }
            rows.append(current.joined(separator: ";"))
            current = []
        }

        for ligne in lignes {
            if estIgnorer(ligne) { continue }
            // TVA avant prix (5,50% serait aussi pris par estPrix modifié)
            if estTVA(ligne) { continue }

            if estTitre(ligne) {
                flush()
                // Extraire un nom exploitable du titre de section (ex: "ARDENCE – CERTIFIÉE BIO" → "Ardence")
                let titreNettoye = ligne
                    .replacingOccurrences(of: #"\s*[–-]\s*CERTIFI.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"\s*[–-]\s*par\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"\s*«.*»\s*"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !titreNettoye.isEmpty && titreNettoye.count >= 2 {
                    dernierNom = titreNettoye.capitalized
                }
                continue
            }

            if estPrix(ligne) {
                // Si on n'a pas de nom dans current, utiliser le dernier nom connu
                if !current.isEmpty {
                    let premierChamp = current[0]
                    if estTaille(premierChamp) || estContenant(premierChamp) {
                        // Pas de nom → ajouter le dernier nom en tête
                        if !dernierNom.isEmpty {
                            current.insert(dernierNom, at: 0)
                        }
                    }
                }
                current.append(ligne)
                flush()
                continue
            }

            if estTaille(ligne) || estContenant(ligne) {
                // Éviter l'accumulation : si current a déjà une taille ET un contenant, flush d'abord
                let aUneTaille = current.contains { estTaille($0) }
                let aUnContenant = current.contains { estContenant($0) }
                if aUneTaille && aUnContenant {
                    flush()
                }
                current.append(ligne)
                continue
            }

            // C'est un nom de produit → terminer l'entrée précédente et commencer une nouvelle
            flush()
            dernierNom = ligne
            current.append(ligne)
        }
        flush()

        return rows.joined(separator: "\n")
    }

    // MARK: - Parsing direct (sans IA)

    /// Pré-traite le texte brut du PDF et le parse directement en produits, sans appel IA.
    /// Retourne la liste de produits si le pré-traitement produit des résultats exploitables, nil sinon.
    func parserDirectement(_ texteBrut: String) -> [ProduitIA]? {
        print("🔵 [PARSER] Texte brut: \(texteBrut.count) car.")
        let pretraite = pretraiterTexte(texteBrut)
        if pretraite.isEmpty {
            print("🔴 [PARSER] Pretraitement vide")
            return nil
        }

        let lignesCSV = pretraite.components(separatedBy: "\n").filter { !$0.isEmpty }
        print("🔵 [PARSER] Pretraitement: \(pretraite.count) car., \(lignesCSV.count) lignes CSV")
        // Afficher les 5 premières et 5 dernières lignes pour diagnostic
        for (i, l) in lignesCSV.prefix(5).enumerated() { print("  CSV[\(i+1)] \(l)") }
        if lignesCSV.count > 10 { print("  ...") }
        for (i, l) in lignesCSV.suffix(5).enumerated() { print("  CSV[\(lignesCSV.count - 4 + i)] \(l)") }

        logDebug("=== PRETRAITEMENT (\(pretraite.count) car., \(lignesCSV.count) lignes) ===\n\(pretraite)\n=== FIN PRETRAITEMENT ===")

        let produits = parserReponseCSV(pretraite)
        let avecPrix = produits.filter { $0.prix > 0 }.count
        print("🔵 [PARSER] Résultat: \(produits.count) produits (\(avecPrix) avec prix)")

        if produits.count >= 2 && avecPrix >= 2 {
            dernierDiagnostic = "Parsing direct: \(produits.count) produits (\(avecPrix) prix)"
            return produits
        }
        print("🔴 [PARSER] Insuffisant")
        return nil
    }

    // MARK: - Découpage en chunks

    /// Découpe le texte en morceaux de `tailleMax` caractères max, en coupant aux fins de ligne.
    private func decouper(texte: String, tailleMax: Int) -> [String] {
        let lignes = texte.components(separatedBy: "\n")
        var chunks: [String] = []
        var chunkActuel = ""

        for ligne in lignes {
            if chunkActuel.count + ligne.count + 1 > tailleMax && !chunkActuel.isEmpty {
                chunks.append(chunkActuel)
                chunkActuel = ""
            }
            if !chunkActuel.isEmpty { chunkActuel += "\n" }
            chunkActuel += ligne
        }
        if !chunkActuel.isEmpty {
            chunks.append(chunkActuel)
        }
        return chunks.isEmpty ? [texte] : chunks
    }

    // MARK: - Traitement d'un chunk

    /// Envoie un seul chunk de texte à l'IA et retourne les produits extraits.
    private func trierChunk(_ texte: String, chunkIndex: Int, totalChunks: Int, completion: @escaping ([ProduitIA]?) -> Void) {
        let userMessage = "Texte brut extrait d'un PDF de tarifs professionnel :\n\n\(texte)"

        logDebug("=== CHUNK \(chunkIndex)/\(totalChunks) : \(texte.count) car. ===\n\(texte.prefix(200))...\n=== FIN APERÇU CHUNK ===")

        appelAPI(system: systemPrompt, user: userMessage) { reponse in
            guard let reponse = reponse else {
                self.logDebug("=== CHUNK \(chunkIndex)/\(totalChunks) : AUCUNE REPONSE === diagnostic: \(self.dernierDiagnostic)")
                completion(nil)
                return
            }

            self.logDebug("=== REPONSE CHUNK \(chunkIndex)/\(totalChunks) ===\n\(reponse)\n=== FIN REPONSE ===")

            let nettoye = reponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if nettoye == "AUCUN_PRODUIT" || nettoye.isEmpty {
                self.logDebug("=== CHUNK \(chunkIndex)/\(totalChunks) : aucun produit ===")
                completion(nil)
                return
            }

            let produits = self.parserReponseCSV(nettoye)
            if produits.isEmpty {
                self.logDebug("=== CHUNK \(chunkIndex)/\(totalChunks) : parsing CSV echoue === reponse brute:\n\(reponse)")
            } else {
                self.logDebug("=== CHUNK \(chunkIndex)/\(totalChunks) : \(produits.count) produits extraits ===")
                for (i, p) in produits.prefix(10).enumerated() {
                    self.logDebug("  [\(i)] nom=\(p.nom) | taille=\(p.taille) | couleur=\(p.couleur) | prix=\(p.prix)")
                }
            }
            completion(produits.isEmpty ? nil : produits)
        }
    }

    // MARK: - Parser la réponse IA

    /// Parse le CSV renvoyé par l'IA (NOM;VOLUME;CONTENANT;PRIX) en liste de ProduitIA.
    private func parserReponseCSV(_ csv: String) -> [ProduitIA] {
        var produits: [ProduitIA] = []

        let lignes = csv.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for ligne in lignes {
            // Ignorer les lignes qui ressemblent à un en-tête, du markdown ou du texte libre
            let low = ligne.lowercased()
            if low.hasPrefix("nom") || low.hasPrefix("variante") || low.hasPrefix("produit") ||
               low.hasPrefix("```") || low.hasPrefix("---") || low.hasPrefix("designation") ||
               low.hasPrefix("désignation") || low.hasPrefix("|") {
                continue
            }

            let parts = ligne.components(separatedBy: ";")
            guard parts.count >= 1 else { continue }

            func clean(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines)
                 .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }

            let nom = clean(parts[0])
            guard !nom.isEmpty, nom.count >= 2 else { continue }
            // Ignorer les noms qui ne sont qu'un prix ou un taux TVA
            if nom.range(of: #"^\d+[.,]\d{1,2}\s*[€%]?$"#, options: .regularExpression) != nil { continue }

            let taille = parts.count >= 2 ? clean(parts[1]) : ""
            var couleur = parts.count >= 3 ? clean(parts[2]) : ""

            var prix: Double = 0
            if parts.count >= 5 {
                // 5+ champs : chercher le prix depuis la fin
                for idx in stride(from: parts.count - 1, through: 3, by: -1) {
                    let prixStr = clean(parts[idx])
                        .replacingOccurrences(of: ",", with: ".")
                        .replacingOccurrences(of: "€", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let p = Double(prixStr), p > 0 {
                        prix = p
                        break
                    }
                }
            } else if parts.count == 4 {
                let prixStr = clean(parts[3])
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "€", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                prix = Double(prixStr) ?? 0
            } else if parts.count == 3 {
                // Fallback : si 3 colonnes, parts[2] peut être un prix (NOM;TAILLE;PRIX)
                let prixStr = clean(parts[2])
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "€", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let p = Double(prixStr) {
                    prix = p
                    couleur = ""  // parts[2] était un prix, pas un contenant
                }
            }

            // Ignorer les lignes avec un prix qui ressemble à un taux TVA (ex: 5.50, 20.0)
            // Heuristique : si le prix est un taux TVA courant ET le nom est très court
            // on ne filtre pas ici, le prompt devrait gérer

            produits.append(ProduitIA(nom: nom, taille: taille, couleur: couleur, prix: prix))
        }

        return produits
    }

    // MARK: - Appel API OpenAI

    /// Dernier diagnostic de l'appel API (pour affichage à l'utilisateur)
    var dernierDiagnostic: String = ""

    private func appelAPI(system: String, user: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            dernierDiagnostic = "URL API invalide"
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(cleAPI)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.0,
            "max_tokens": 8000,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            dernierDiagnostic = "Erreur encodage JSON"
            logDebug("=== ERREUR : impossible d'encoder le body JSON ===")
            completion(nil)
            return
        }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            // Vérifier les erreurs réseau
            if let error = error {
                let msg = "Erreur reseau : \(error.localizedDescription)"
                self.logDebug("=== ERREUR API === \(msg)")
                DispatchQueue.main.async {
                    self.dernierDiagnostic = msg
                    completion(nil)
                }
                return
            }

            // Vérifier le code HTTP
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            self.logDebug("=== HTTP STATUS : \(httpStatus) ===")

            guard let data = data else {
                let msg = "Aucune donnee recue (HTTP \(httpStatus))"
                self.logDebug("=== ERREUR API === \(msg)")
                DispatchQueue.main.async {
                    self.dernierDiagnostic = msg
                    completion(nil)
                }
                return
            }

            // Tenter de parser le JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let raw = String(data: data.prefix(500), encoding: .utf8) ?? "(binaire)"
                let msg = "Reponse non-JSON (HTTP \(httpStatus)) : \(raw)"
                self.logDebug("=== ERREUR API === \(msg)")
                DispatchQueue.main.async {
                    self.dernierDiagnostic = msg
                    completion(nil)
                }
                return
            }

            // Vérifier si l'API retourne une erreur
            if let apiError = json["error"] as? [String: Any] {
                let errorMsg = apiError["message"] as? String ?? "erreur inconnue"
                let errorType = apiError["type"] as? String ?? ""
                let msg = "Erreur OpenAI (\(errorType)) : \(errorMsg)"
                self.logDebug("=== ERREUR API === \(msg)")
                DispatchQueue.main.async {
                    self.dernierDiagnostic = msg
                    completion(nil)
                }
                return
            }

            // Extraire le contenu de la réponse
            guard let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                let msg = "Format reponse inattendu (HTTP \(httpStatus))"
                self.logDebug("=== ERREUR API === \(msg) json=\(json)")
                DispatchQueue.main.async {
                    self.dernierDiagnostic = msg
                    completion(nil)
                }
                return
            }

            // Détecter si la réponse a été tronquée par le token limit
            let finishReason = firstChoice["finish_reason"] as? String ?? "unknown"
            if finishReason == "length" {
                print("⚠️ [IA] Réponse tronquée (finish_reason=length) — certains produits peuvent manquer")
                self.logDebug("=== ATTENTION : RÉPONSE TRONQUÉE (finish_reason=length) ===")
            }

            self.logDebug("=== SUCCES API === \(content.count) caracteres recus, finish_reason=\(finishReason)")
            DispatchQueue.main.async {
                self.dernierDiagnostic = "OK (\(content.count) car.)"
                completion(content)
            }
        }.resume()
    }

    // MARK: - Debug log

    /// Ecrit un log de debug dans Documents/ai_debug.txt (pour diagnostiquer les imports).
    func logDebug(_ message: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logURL = docs.appendingPathComponent("ai_debug.txt")
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)\n\n"
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? entry.data(using: .utf8)?.write(to: logURL)
        }
    }
}
