import SwiftUI
import SwiftData
import PocketProCore

/// Bowler profile (PRD 5.4.1): PAP is primary — referenced throughout the layout
/// system. Secondary fields stored for reference and the v3 recommendation engine.
struct BowlerProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BowlerProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                ProfileForm(profile: profile)
            } else {
                ProgressView()
                    .onAppear {
                        context.insert(BowlerProfile())
                    }
            }
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: BowlerProfile

    var body: some View {
        Form {
            Section("Bowler") {
                TextField("Display name", text: $profile.displayName)
                Picker("Default ball weight", selection: $profile.defaultBallWeight) {
                    ForEach(12...16, id: \.self) { lbs in
                        Text("\(lbs) lb").tag(lbs)
                    }
                }
                Picker("Grip type", selection: Binding(
                    get: { profile.defaultGripType },
                    set: { profile.defaultGripType = $0 }
                )) {
                    ForEach(GripType.allCases) { grip in
                        Text(grip.displayName).tag(grip)
                    }
                }
            }

            Section {
                measureField("Inches over", value: $profile.papOver)
                measureField("Inches up (+) / down (–)", value: $profile.papUp)
                if profile.papOver != nil {
                    LabeledContent("PAP", value: profile.papDisplay)
                }
            } header: {
                Text("Positive Axis Point — Primary")
            } footer: {
                Text("Used by the layout system to contextualize Dual Angle and VLS measurements. Get it measured at your pro shop if unsure.")
            }

            Section {
                measureField("Ball speed (mph)", value: $profile.ballSpeedMPH)
                measureField("Rev rate (rpm)", value: $profile.revRate)
                measureField("Axis tilt (°)", value: $profile.axisTilt)
                measureField("Axis rotation (°)", value: $profile.axisRotation)
            } header: {
                Text("Release — Secondary")
            } footer: {
                Text("Stored for reference and the future layout recommendation engine. TenPin Toolkit measures tilt and rotation.")
            }
        }
        .navigationTitle("Bowler Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func measureField(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            // numbersAndPunctuation: PAP up/down accepts negative values.
            OptionalNumberField(placeholder: "—", value: value, keyboard: .numbersAndPunctuation)
                .frame(width: 90)
        }
    }
}
