import Foundation

/// Coverstock families (PRD 5.4.3). Raw values are storage/JSON keys.
public enum CoverstockType: String, Codable, CaseIterable, Sendable, Identifiable {
    case solid
    case pearl
    case hybrid
    case urethane
    case polyester

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .pearl: return "Pearl"
        case .hybrid: return "Hybrid"
        case .urethane: return "Urethane"
        case .polyester: return "Polyester"
        }
    }
}

/// One ball record from the Pocket Pro ball database (PRD §9).
/// Decoded from the bundled seed `balldb.json` today; the same schema is the
/// OTA-update contract for the server pipeline output.
public struct BallDBRecord: Codable, Identifiable, Hashable, Sendable {
    public struct WeightSpec: Codable, Hashable, Sendable {
        public let rg: Double
        public let diff: Double
        public let intDiff: Double?

        public init(rg: Double, diff: Double, intDiff: Double?) {
            self.rg = rg
            self.diff = diff
            self.intDiff = intDiff
        }

        enum CodingKeys: String, CodingKey {
            case rg
            case diff
            case intDiff = "int_diff"
        }
    }

    public let id: String
    public let manufacturer: String
    public let brand: String
    /// "active" or "retired" (Columbia 300 is a retired brand — PRD 9.1).
    public let brandStatus: String
    public let model: String
    public let year: Int?
    public let coverstockType: CoverstockType
    public let coverstockName: String?
    public let coreName: String?
    public let asymmetric: Bool
    public let factoryFinish: String?
    /// Product photo URL from the ball database (token-free original). nil if unknown.
    public let imageURL: String?
    /// Specs keyed by weight string "12"..."16" (PRD 9.4).
    public let specsByWeight: [String: WeightSpec]
    /// Brunswick shared-core linkage (PRD 5.4.2): records sharing a core carry the same ID.
    public let sharedCoreID: String?
    /// "approved" | "staged" | "seed".
    public let dbStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case manufacturer
        case brand
        case brandStatus = "brand_status"
        case model
        case year
        case coverstockType = "coverstock_type"
        case coverstockName = "coverstock_name"
        case coreName = "core_name"
        case asymmetric
        case factoryFinish = "factory_finish"
        case imageURL = "image_url"
        case specsByWeight = "specs_by_weight"
        case sharedCoreID = "shared_core_id"
        case dbStatus = "db_status"
    }

    public init(
        id: String,
        manufacturer: String,
        brand: String,
        brandStatus: String,
        model: String,
        year: Int?,
        coverstockType: CoverstockType,
        coverstockName: String?,
        coreName: String?,
        asymmetric: Bool,
        factoryFinish: String?,
        imageURL: String? = nil,
        specsByWeight: [String: WeightSpec],
        sharedCoreID: String?,
        dbStatus: String
    ) {
        self.id = id
        self.manufacturer = manufacturer
        self.brand = brand
        self.brandStatus = brandStatus
        self.model = model
        self.year = year
        self.coverstockType = coverstockType
        self.coverstockName = coverstockName
        self.coreName = coreName
        self.asymmetric = asymmetric
        self.factoryFinish = factoryFinish
        self.imageURL = imageURL
        self.specsByWeight = specsByWeight
        self.sharedCoreID = sharedCoreID
        self.dbStatus = dbStatus
    }

    /// Spec lookup at the bowler's weight with the PRD 9.4 fallback chain:
    /// exact weight → 15 lb (flagged as fallback) → nil.
    public func spec(atWeight weight: Int) -> (spec: WeightSpec, isFallback: Bool)? {
        if let exact = specsByWeight[String(weight)] {
            return (exact, false)
        }
        if let fallback = specsByWeight["15"] {
            return (fallback, true)
        }
        return nil
    }

    public var displayName: String {
        "\(brand) \(model)"
    }
}

/// The decoded seed/synced database file.
public struct BallDatabaseFile: Codable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let balls: [BallDBRecord]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case balls
    }

    /// Case-insensitive search over brand + model with simple token matching.
    public func search(_ query: String) -> [BallDBRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return balls }
        let tokens = trimmed.split(separator: " ").map(String.init)
        return balls.filter { ball in
            let haystack = "\(ball.brand) \(ball.model)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}
