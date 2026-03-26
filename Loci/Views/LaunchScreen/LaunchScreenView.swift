import SwiftUI

/// Launch screen displayed while the app initializes.
/// Also used as a visual reference for the Info.plist launch screen configuration.
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.white)

                Text("Loci")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your Spatial Memory")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
