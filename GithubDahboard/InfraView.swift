import SwiftUI

struct InfraView: View {
    let inventaire: Inventaire?
    let message: String?

    var body: some View {
        if let inventaire {
            VStack(alignment: .leading, spacing: 16) {
                header(inventaire)
                if Date().timeIntervalSince(inventaire.genereLe) > 36 * 60 * 60 {
                    Text("Le plan de nuit n'a pas tourné depuis plus de 36 h.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if !inventaire.ecarts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Écarts").font(.headline)
                        ForEach(inventaire.ecarts, id: \.adresse) { ecart in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ecart.adresse).font(.caption).monospaced()
                                Text(ecart.actions.joined(separator: ", "))
                            }
                        }
                    }
                }
                let groups = Dictionary(grouping: inventaire.machines) { $0.noeud ?? "Autre" }
                ForEach(groups.keys.sorted(), id: \.self) { noeud in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(noeud).font(.headline)
                        ForEach(groups[noeud, default: []].sorted { ($0.vmid ?? Int.max) < ($1.vmid ?? Int.max) }) { machine in
                            machineRow(machine)
                            if machine.id != groups[noeud, default: []].last?.id { Divider() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("Pas d'inventaire", systemImage: "server.rack", description: Text(message ?? ""))
        }
    }

    private func header(_ inventaire: Inventaire) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                inventaire.statut == "ok" ? "Conforme au code" : "Dérive détectée",
                systemImage: inventaire.statut == "ok" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(inventaire.statut == "ok" ? .green : .red)
            HStack(spacing: 8) {
                Text("Dernier contrôle")
                Text(inventaire.genereLe, style: .relative)
                if let execution = inventaire.execution {
                    Link("Voir l'exécution", destination: execution)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func machineRow(_ machine: InventaireMachine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(machine.demarre == true ? .green : .gray)
                    .accessibilityLabel(machine.demarre == true ? "Démarrée" : "Arrêtée")
                Text(machine.hote ?? machine.nom).bold()
                Spacer()
                if let vmid = machine.vmid {
                    Text("\(machine.type.uppercased()) \(vmid)")
                        .foregroundStyle(.secondary)
                }
            }
            if let ipv4 = machine.ipv4 {
                Text(ipv4).font(.caption).monospaced().textSelection(.enabled)
            }
            let resources = [
                machine.coeurs.map { "\($0) cœurs" },
                machine.memoireMo.map { "\($0) Mo" },
                machine.disqueGo.map { "\($0) Go" }
            ].compactMap { $0 }
            if !resources.isEmpty {
                Text(resources.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let etiquettes = machine.etiquettes, !etiquettes.isEmpty {
                HStack {
                    ForEach(etiquettes, id: \.self) { etiquette in
                        Text(etiquette)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
        }
    }
}

#Preview("Conforme") {
    InfraView(inventaire: InventairePreviewData.ok, message: nil)
        .padding()
}

#Preview("Dérive") {
    InfraView(inventaire: InventairePreviewData.derive, message: nil)
        .padding()
}

private enum InventairePreviewData {
    static let date = ISO8601DateFormatter().date(from: "2026-09-30T19:41:43Z")!
    static let ok = InventairePreview.make(status: "ok", machines: [
        .init(adresse: "ct-a", nom: "forgejo", noeud: "pve-a", type: "ct", vmid: 105, hote: "forgejo", ipv4: "192.168.1.10/24", coeurs: 2, memoireMo: 512, disqueGo: 4, demarre: true, etiquettes: ["infra", "git"]),
        .init(adresse: "vm-a", nom: "runner", noeud: "pve-a", type: "vm", vmid: 200, hote: nil, ipv4: "192.168.1.11/24", coeurs: 4, memoireMo: 4096, disqueGo: 32, demarre: true, etiquettes: ["ci"]),
        .init(adresse: "ct-b", nom: "vault", noeud: "pve-b", type: "ct", vmid: 106, hote: "vault", ipv4: nil, coeurs: 1, memoireMo: 512, disqueGo: 4, demarre: false, etiquettes: nil)
    ])
    static let derive = InventairePreviewData.make(status: "derive", machines: [
        .init(adresse: "ct-a", nom: "forgejo", noeud: "pve-a", type: "ct", vmid: 105, hote: nil, ipv4: nil, coeurs: nil, memoireMo: nil, disqueGo: nil, demarre: true, etiquettes: nil)
    ], ecarts: [InventaireEcart(adresse: "ct-a", actions: ["update"])])
}

private enum InventairePreview {
    static func make(status: String, machines: [InventaireMachine], ecarts: [InventaireEcart] = []) -> Inventaire {
        Inventaire(genereLe: InventairePreviewData.date, commit: "preview", execution: URL(string: "https://github.com"), statut: status, ecarts: ecarts, machines: machines)
    }
}
