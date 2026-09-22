import SwiftUI

/// Shown whenever the situation is an emergency, above anything about
/// insurance. Paperwork can wait; a person in danger cannot, and an app that
/// walks someone through claim steps before telling them to call for help has
/// its priorities backwards.
struct EmergencyCallCard: View {
    private let number = EmergencyNumber.forCurrentRegion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Label(String(localized: "Call for help first"), systemImage: "staroflife.fill")
                .font(.headline)
                .foregroundStyle(Theme.Palette.caution)

            Text(String(localized: "If someone's life or health is at risk, call emergency services now. The insurance can wait until everyone is safe."))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: "tel://\(number)") {
                Link(destination: url) {
                    Label(String(localized: "Call \(number)"), systemImage: "phone.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint(String(localized: "Calls the emergency number for your region"))
            }
        }
        .padding(Theme.Spacing.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coveraCard(accent: Theme.Palette.caution)
    }
}

/// The ambulance or general emergency number for where the phone is set up,
/// falling back to 112, which mobile networks route to emergency services in
/// most countries.
enum EmergencyNumber {
    static var forCurrentRegion: String {
        switch Locale.current.region?.identifier {
        case "IL": "101"                    // Magen David Adom
        case "US", "CA", "MX": "911"
        case "AU": "000"
        case "NZ": "111"
        case "JP": "119"
        case "BR": "192"                    // SAMU
        case "TH": "1669"
        default: "112"
        }
    }
}
