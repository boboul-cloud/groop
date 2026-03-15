//
//  PlusReglageView.swift
//  coquilles
//
//  Configuration, remise à zéro et import de clients.
//

import SwiftUI
import UniformTypeIdentifiers

struct PlusReglageView: View {
    @ObservedObject var store: OrderStore

    @State private var showCampagneSetup = false
    @State private var showConfirmReset = false
    @State private var showImportClients = false
    @State private var importClientsCount = 0
    @State private var showImportClientsFeedback = false
    @State private var exportClientsShareItem: IdentifiableURL? = nil

    private let confidentialiteURL = URL(string: "https://boboul-cloud.github.io/coquilles/confidentialite.html")!
    private let conditionsURL = URL(string: "https://boboul-cloud.github.io/coquilles/conditions.html")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                reglagesSection
                confidentialiteSection
                versionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCampagneSetup) {
            CampagneSetupView(store: store)
        }
        .alert("Remise à zéro", isPresented: $showConfirmReset) {
            Button("Confirmer", role: .destructive) {
                store.remiseAZero()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Toutes les commandes seront effacées. Les noms et téléphones des clients seront conservés.")
        }
        .fileImporter(isPresented: $showImportClients, allowedContentTypes: [.plainText, .commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                importClientsCount = store.importerClientsDepuisFichier(url: url)
                if importClientsCount > 0 {
                    showImportClientsFeedback = true
                }
            case .failure:
                break
            }
        }
        .alert("\(importClientsCount) client\(importClientsCount > 1 ? "s" : "") importé\(importClientsCount > 1 ? "s" : "") ✓", isPresented: $showImportClientsFeedback) {
            Button("OK") {}
        }
        .sheet(item: $exportClientsShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Réglages

    private var reglagesSection: some View {
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

            Button {
                showImportClients = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Importer une liste de clients")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.ocean.opacity(0.1))
                .foregroundStyle(.ocean)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                if let url = store.exporterClientsFichier() {
                    exportClientsShareItem = IdentifiableURL(url: url)
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.arrow.right")
                    Text("Exporter la liste de clients")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(store.orders.filter { !$0.nom.isEmpty }.count)")
                        .font(.caption)
                        .foregroundStyle(.ocean)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.ocean.opacity(0.15))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.ocean.opacity(0.1))
                .foregroundStyle(.ocean)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(store.orders.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Confidentialité et conditions

    private var confidentialiteSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.ocean)
                Text("Confidentialité et conditions")
                    .font(.headline)
                    .foregroundStyle(.ocean)
                Spacer()
            }

            Link(destination: confidentialiteURL) {
                HStack {
                    Image(systemName: "lock.shield")
                    Text("Politique de confidentialité")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Link(destination: conditionsURL) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("Conditions d'utilisation")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
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
    }

    // MARK: - Version et copyright

    private var versionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.ocean)
                Text("À propos")
                    .font(.headline)
                    .foregroundStyle(.ocean)
                Spacer()
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .fontWeight(.medium)
                }

                Divider()

                HStack {
                    Text("Développeur")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Robert Oulhen")
                        .fontWeight(.medium)
                }

                Divider()

                Text("© \(Calendar.current.component(.year, from: Date())) Robert Oulhen. Tous droits réservés.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
