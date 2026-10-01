import Foundation
import Observation

/// One contact with an insurer: a call, an email, a letter, a visit.
///
/// Everything here is typed by the user, so there is nothing to verify against
/// a document and nothing a model could invent. That is the point of the
/// feature — in a dispute the person holding dates, names and reference
/// numbers is the one who can prove what happened.
struct CallLogEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case call, email, letter, visit
        var id: String { rawValue }

        var label: String {
            switch self {
            case .call: String(localized: "Call")
            case .email: String(localized: "Email")
            case .letter: String(localized: "Letter")
            case .visit: String(localized: "Visit")
            }
        }

        var icon: String {
            switch self {
            case .call: "phone"
            case .email: "envelope"
            case .letter: "doc.plaintext"
            case .visit: "building.2"
            }
        }
    }

    var id = UUID()
    var date = Date()
    var kind: Kind = .call
    /// The policy this contact was about, when it was about one.
    var documentID: String?
    var policyName: String?
    /// Who answered. A name is worth more than a department.
    var person = ""
    /// The reference the insurer gave for the conversation.
    var reference = ""
    /// What was said, and what was promised.
    var notes = ""
    /// What was handed over: receipts, a form, a doctor's letter.
    var sent = ""
}

/// The log, kept on the device only.
///
/// These notes are the user's own account of what an insurer said. They are
/// never uploaded: nothing on the server needs them, and a record of a dispute
/// with an insurer is exactly the kind of thing that should stay on the phone.
@Observable
final class CallLogStore {
    private(set) var entries: [CallLogEntry] = []
    /// Set when the log could not be read or saved, so an edit is never lost
    /// silently. Shown by the call log screen.
    private(set) var problem: String?

    private let fileURL: URL?

    /// One file per account. Without an account there is nothing to show and
    /// nothing is written.
    init(accountID: String?) {
        Self.discardUnownedLog()
        guard let accountID, let url = Self.url(for: accountID) else {
            fileURL = nil
            return
        }
        fileURL = url
        load()
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func url(for accountID: String) -> URL? {
        // The id is a server UUID; anything else is refused rather than used in a path.
        guard UUID(uuidString: accountID) != nil else { return nil }
        return directory.appendingPathComponent("call-log-\(accountID.lowercased()).json")
    }

    /// Before logs were filed by account there was one shared `call-log.json`.
    /// Its owner cannot be known, so it is given to no one. (Clausa had not
    /// launched; the only notes in it were test data.)
    private static func discardUnownedLog() {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("call-log.json"))
    }

    /// Removes an account's log from this device, after the account is deleted.
    static func erase(accountID: String) {
        if let url = url(for: accountID) { try? FileManager.default.removeItem(at: url) }
    }

    #if DEBUG
    /// Sample entries for the demo build; never written to disk.
    init(sample: [CallLogEntry]) {
        fileURL = nil
        entries = sample
    }
    #endif

    func entries(for documentID: String?) -> [CallLogEntry] {
        guard let documentID else { return entries }
        return entries.filter { $0.documentID == documentID }
    }

    func save(_ entry: CallLogEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        // Newest first: a claim is followed from its most recent contact.
        entries.sort { $0.date > $1.date }
        write()
    }

    func delete(_ entry: CallLogEntry) {
        entries.removeAll { $0.id == entry.id }
        write()
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            entries = try JSONDecoder().decode([CallLogEntry].self, from: Data(contentsOf: fileURL))
        } catch {
            problem = String(localized: "Your call log could not be read on this device.")
        }
    }

    private func write() {
        guard let fileURL else { return }
        do {
            // Written with file protection, like everything else the app keeps.
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic, .completeFileProtection])
            problem = nil
        } catch {
            problem = String(localized: "This change could not be saved on this device.")
        }
    }

    /// The whole log as one page of plain text, for sending to an insurer,
    /// a lawyer or an ombudsman.
    func transcript(for documentID: String? = nil) -> String {
        let rows = entries(for: documentID)
        guard !rows.isEmpty else { return String(localized: "No contacts recorded yet.") }
        return rows.map { entry in
            var lines = [
                "\(entry.date.formatted(.coveraDate.day().month().year().hour().minute())) — \(entry.kind.label)",
            ]
            if let name = entry.policyName, !name.isEmpty {
                lines.append("\(String(localized: "Policy")): \(name)")
            }
            if !entry.person.isEmpty { lines.append("\(String(localized: "Spoke with")): \(entry.person)") }
            if !entry.reference.isEmpty {
                lines.append("\(String(localized: "Reference number")): \(entry.reference)")
            }
            if !entry.notes.isEmpty { lines.append("\(String(localized: "What was said")): \(entry.notes)") }
            if !entry.sent.isEmpty { lines.append("\(String(localized: "What you sent")): \(entry.sent)") }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
