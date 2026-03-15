//
//  MessagesExportView.swift
//  coquilles
//
//  Page « Plus » – navigation vers les sous-sections.
//

import SwiftUI

struct MessagesExportView: View {
    @ObservedObject var store: OrderStore

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PlusExportationView(store: store)
                } label: {
                    Label {
                        Text("Exportation")
                    } icon: {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.ocean)
                    }
                }

                NavigationLink {
                    PlusCommandeView(store: store)
                } label: {
                    Label {
                        Text("Commande")
                    } icon: {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.ocean)
                    }
                }

                NavigationLink {
                    PlusCampagneView(store: store)
                } label: {
                    Label {
                        Text("Campagne")
                    } icon: {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.ocean)
                    }
                }

                NavigationLink {
                    PlusReglageView(store: store)
                } label: {
                    Label {
                        Text("Réglages")
                    } icon: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.ocean)
                    }
                }
            }
            .navigationTitle("Plus")
        }
    }
}
