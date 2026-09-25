#if DEBUG
import Foundation

/// Fictional sample data for Xcode previews and the `-CoveraDemo` launch
/// argument. Compiled out of release builds entirely.
///
/// It still obeys the rule: every figure in a step appears in that step's own
/// quote, and the summary repeats only figures a step proved. Sample data that
/// breaks the contract would make the design look better than the product can
/// honestly be.
enum PreviewData {
    /// True when launched with `-CoveraDemo`, so screenshots can be taken
    /// without a running API.
    static var isDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-CoveraDemo")
    }

    /// The screen a demo launch opens on, for App Store screenshots:
    /// `-CoveraDemo -CoveraShot plan` (home, plan, policies, ask, calllog).
    static var shot: String? {
        isDemo ? UserDefaults.standard.string(forKey: "CoveraShot") : nil
    }

    /// A plan in progress: the intake answered, the first step marked done.
    @MainActor
    static func guidanceModel() -> GuidanceModel {
        GuidanceModel(
            sampleKind: .surgery,
            details: "My daughter needs knee arthroscopy next month, with a private surgeon.",
            recipient: .child,
            timing: .weeks,
            referral: .unsure,
            plan: plan,
            completed: [1]
        )
    }

    private static let documentID = "3f1c2a9e-5b7d-4e21-9c3a-8d6f0b1e2a47"

    static let plan = GuidanceResponse(
        disclaimer: "Covera is not a doctor and not a licensed insurance agent. This is a reading of your own documents, not medical advice and not a coverage decision. Your insurer decides what is covered.",
        clarifyingQuestions: [
            ClarifyingQuestion(
                question: "Is the surgeon in your insurer’s network?",
                why: "Your policy treats in-network and private surgeons differently."
            ),
        ],
        summary: "Your supplementary policy covers planned surgery once the Fund has approved it in advance. After the operation you have 90 days to submit the claim.",
        steps: [
            ActionStep(
                order: 1,
                action: "Ask the Fund for prior approval before booking the operation.",
                deadlineNote: nil,
                basis: .cited(SourceCitation(
                    documentID: documentID,
                    page: 7,
                    clauseRef: "§14.2",
                    verbatimQuote: "Planned surgery is covered only with prior written approval from the Fund."
                ))
            ),
            ActionStep(
                order: 2,
                action: "Confirm whether a referral from your family doctor is required.",
                deadlineNote: nil,
                basis: .notStated(
                    ask: "Do I need a referral from my family doctor before a private knee operation?",
                    insurerPhone: "*2700"
                )
            ),
            ActionStep(
                order: 3,
                action: "Keep the original itemised invoice and the surgeon’s operative report.",
                deadlineNote: nil,
                basis: .general
            ),
            ActionStep(
                order: 4,
                action: "Submit the claim with the invoice and report within 90 days of the operation.",
                deadlineNote: "Within 90 days of the operation",
                basis: .cited(SourceCitation(
                    documentID: documentID,
                    page: 12,
                    clauseRef: "§21",
                    verbatimQuote: "A claim must be submitted within 90 days of the operation."
                ))
            ),
        ],
        conflicts: [],
        phoneScript: "Hello, I’m calling about my daughter’s planned knee surgery. I’d like to request prior approval, and to ask whether a referral from our family doctor is required first.",
        // The only figure here is the 90 days, which step 4's quote proves.
        draftClaimEmail: "Dear Claims Team,\n\nI am submitting a claim for my daughter’s knee arthroscopy on [date of operation]. Please find attached the itemised invoice and the surgeon’s operative report.\n\nI understand the policy asks for claims within 90 days of the operation.\n\nKind regards,\n[Your name]\n[Policy number]",
        relevantPolicyIDs: [],
        withheld: [
            "A step about \"physiotherapy after surgery\" was withheld: it states a figure the quoted text does not contain",
        ],
        includesTranscribedPages: true
    )

    /// Every figure is inside its citation's quote, as the server requires.
    static let chatReply = ChatReply(
        answer: "Claims must be submitted within 90 days of the operation. Your policy does not say whether a family doctor's referral is needed.",
        citations: [SourceCitation(documentID: documentID, page: 12, clauseRef: "§21", verbatimQuote: "A claim must be submitted within 90 days of the operation.")],
        askInsurer: "Do I need a referral from my family doctor before a private operation?",
        withheld: false,
        disclaimer: plan.disclaimer
    )

    static let documents: [PolicyDocument] = [
        PolicyDocument(
            id: documentID,
            originalFilename: "Supplementary Health — Policy Wording 2026.pdf",
            status: "extracted",
            pageCount: 48,
            uploadedAt: Date(timeIntervalSinceNow: -3_600 * 5)
        ),
        PolicyDocument(
            id: "8a2e41c7-0d93-4b5f-a1e6-2c7b9f3d5e10",
            originalFilename: "Private Surgery Plan.pdf",
            status: "extracted",
            pageCount: 31,
            uploadedAt: Date(timeIntervalSinceNow: -86_400 * 12)
        ),
        PolicyDocument(
            id: "c4d9b2f1-7e3a-4c86-b0d5-9a1f6e2c8b73",
            originalFilename: "Dental cover scan.pdf",
            status: "failed",
            pageCount: nil,
            uploadedAt: Date(timeIntervalSinceNow: -86_400 * 40)
        ),
    ]

    /// Two contacts about the surgery plan, as someone mid-claim would have.
    static let callLog: [CallLogEntry] = [
        CallLogEntry(
            date: Date().addingTimeInterval(-86_400 * 2),
            kind: .call,
            policyName: "Private Surgery Plan",
            person: "Dana, claims department",
            reference: "CL-4471-22",
            notes: "Said the pre-approval form and the surgeon's letter are enough, and that a decision takes ten working days.",
            sent: "Pre-approval form, surgeon's letter"
        ),
        CallLogEntry(
            date: Date().addingTimeInterval(-86_400 * 9),
            kind: .email,
            policyName: "Supplementary Health — Policy Wording 2026",
            person: "Service desk",
            reference: "TKT-88190",
            notes: "Asked which hospitals count as in-network for a planned operation.",
            sent: "Referral letter"
        ),
    ]
}
#endif
