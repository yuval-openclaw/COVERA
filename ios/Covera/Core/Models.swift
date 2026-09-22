import Foundation

/// Wire types for the Covera API.
///
/// `StepBasis` mirrors the server's discriminated union deliberately. The server
/// cannot express a figure without a citation; neither can this client. If the
/// two shapes ever drift, decoding fails loudly rather than rendering a number
/// with nothing behind it.

struct SourceCitation: Codable, Hashable {
    let documentID: String
    let page: Int
    let clauseRef: String?
    let verbatimQuote: String

    enum CodingKeys: String, CodingKey {
        case documentID = "document_id"
        case page
        case clauseRef = "clause_ref"
        case verbatimQuote = "verbatim_quote"
    }
}

enum StepBasis: Hashable {
    case cited(SourceCitation)
    case notStated(ask: String, insurerPhone: String?)
    case general
}

extension StepBasis: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, citation
        case askInsurer = "ask_insurer"
        case insurerPhone = "insurer_phone"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "cited":
            self = .cited(try container.decode(SourceCitation.self, forKey: .citation))
        case "not_stated":
            self = .notStated(
                ask: try container.decode(String.self, forKey: .askInsurer),
                insurerPhone: try container.decodeIfPresent(String.self, forKey: .insurerPhone)
            )
        case "general":
            self = .general
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown step basis '\(other)'. Refusing to display a step we cannot attribute."
            )
        }
    }
}

struct ActionStep: Decodable, Identifiable, Hashable {
    let order: Int
    let action: String
    let deadlineNote: String?
    let basis: StepBasis

    var id: Int { order }

    enum CodingKeys: String, CodingKey {
        case order, action, basis
        case deadlineNote = "deadline_note"
    }
}

struct ClarifyingQuestion: Decodable, Identifiable, Hashable {
    let question: String
    let why: String
    var id: String { question }
}

struct GuidanceResponse: Decodable {
    let disclaimer: String
    let clarifyingQuestions: [ClarifyingQuestion]
    let summary: String
    let steps: [ActionStep]
    let conflicts: [String]
    let phoneScript: String?
    let draftClaimEmail: String?
    let relevantPolicyIDs: [String]
    /// Steps the server refused to show because their citation did not check out.
    let withheld: [String]
    /// True when some evidence came from a page we transcribed ourselves.
    let includesTranscribedPages: Bool

    enum CodingKeys: String, CodingKey {
        case disclaimer, summary, steps, conflicts, withheld
        case clarifyingQuestions = "clarifying_questions"
        case phoneScript = "phone_script"
        case draftClaimEmail = "draft_claim_email"
        case relevantPolicyIDs = "relevant_policy_ids"
        case includesTranscribedPages = "includes_transcribed_pages"
    }
}

struct PolicyDocument: Decodable, Identifiable, Hashable {
    let id: String
    let originalFilename: String
    let status: String
    let pageCount: Int?
    let uploadedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case originalFilename = "original_filename"
        case pageCount = "page_count"
        case uploadedAt = "uploaded_at"
    }

    var isReady: Bool { status == "extracted" }

    /// The filename without its extension — how a person would name the policy.
    var displayName: String {
        let trimmed = (originalFilename as NSString).deletingPathExtension
        return trimmed.isEmpty ? originalFilename : trimmed
    }

    var statusDescription: String {
        switch status {
        case "extracted": return String(localized: "Read and stored")
        case "extracting": return String(localized: "Being read…")
        case "uploaded": return String(localized: "Waiting to be read")
        case "failed": return String(localized: "Could not be read")
        default: return status
        }
    }
}

struct DocumentListResponse: Decodable {
    let documents: [PolicyDocument]
}

struct UploadResponse: Decodable {
    let documentID: String
    let policyID: String?
    let supersedes: String?
    let changes: [PolicyChange]
    let transcribedPages: [Int]
    let alreadyIngested: Bool

    enum CodingKeys: String, CodingKey {
        case changes
        case documentID = "document_id"
        case policyID = "policy_id"
        case supersedes = "supersedes_policy_id"
        case transcribedPages = "transcribed_pages"
        case alreadyIngested = "already_ingested"
    }
}

/// A renewal difference. The server guarantees `summary` carries no figure that
/// is not also present in the underlying before/after fields, so it is safe to
/// show as prose; the raw fields are not decoded because the client has no
/// reason to re-render a citation the server already checked.
struct PolicyChange: Decodable, Identifiable, Hashable {
    let path: String
    let kind: String
    let summary: String
    var id: String { path + kind }

    enum CodingKeys: String, CodingKey {
        case path, kind, summary
    }
}

struct ChatReply: Decodable {
    let answer: String
    let citations: [SourceCitation]
    let askInsurer: String?
    /// The server could not verify its draft and replaced it.
    let withheld: Bool
    let disclaimer: String

    enum CodingKeys: String, CodingKey {
        case answer, citations, withheld, disclaimer
        case askInsurer = "ask_insurer"
    }
}
