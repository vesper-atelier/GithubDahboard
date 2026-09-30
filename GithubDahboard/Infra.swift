import Foundation

struct Inventaire: Decodable {
    let genereLe: Date
    let commit: String
    let execution: URL?
    let statut: String
    let ecarts: [InventaireEcart]
    let machines: [InventaireMachine]

    init(genereLe: Date, commit: String, execution: URL?, statut: String, ecarts: [InventaireEcart], machines: [InventaireMachine]) {
        self.genereLe = genereLe
        self.commit = commit
        self.execution = execution
        self.statut = statut
        self.ecarts = ecarts
        self.machines = machines
    }

    enum CodingKeys: String, CodingKey {
        case genereLe = "genere_le"
        case commit, execution, statut, ecarts, machines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(String.self, forKey: .genereLe)
        guard let parsedDate = ISO8601DateFormatter().date(from: date) else {
            throw DecodingError.dataCorruptedError(forKey: .genereLe, in: container, debugDescription: "Date ISO 8601 invalide")
        }
        genereLe = parsedDate
        commit = try container.decode(String.self, forKey: .commit)
        execution = try container.decodeIfPresent(URL.self, forKey: .execution)
        statut = try container.decode(String.self, forKey: .statut)
        ecarts = try container.decodeIfPresent([InventaireEcart].self, forKey: .ecarts) ?? []
        machines = try container.decodeIfPresent([InventaireMachine].self, forKey: .machines) ?? []
    }
}

struct InventaireEcart: Decodable {
    let adresse: String
    let actions: [String]
}

struct InventaireMachine: Decodable, Identifiable {
    let adresse: String
    let nom: String
    let noeud: String?
    let type: String
    let vmid: Int?
    let hote: String?
    let ipv4: String?
    let coeurs: Int?
    let memoireMo: Int?
    let disqueGo: Int?
    let demarre: Bool?
    let etiquettes: [String]?

    var id: String { adresse }

    enum CodingKeys: String, CodingKey {
        case adresse, nom, noeud, type, vmid, hote, ipv4, coeurs
        case memoireMo = "memoire_mo"
        case disqueGo = "disque_go"
        case demarre, etiquettes
    }
}
