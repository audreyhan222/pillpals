import SwiftUI

struct LandingView: View {
    @State private var showButtons = false
    @State private var logoOffset: CGFloat = 150
    @State private var logoOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    .gradientBlue,
                    .gradientYellow,
                    .gradientPink
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Logo and Title Section
                VStack(spacing: 16) {
                    // Logo Container
                    ZStack {
                        // Glowing background effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .logoGradientStart,
                                        .logoGradientEnd
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blur(radius: 30)
                            .scaleEffect(animatingGlow ? 1.2 : 1.0)
                            .opacity(animatingGlow ? 0.5 : 0.3)

                        // Main logo rounded square
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .logoGradientStart,
                                        .logoGradientEnd
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 112, height: 112)
                            .shadow(color: .backgroundGlowShadow, radius: 20)
                        
                        // Heart icon
                        Image(systemName: "heart.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 140, height: 140)
                    .offset(y: logoOffset)
                    .opacity(logoOpacity)
                    
                    // Title
                    HStack(spacing: 0) {
                        Text("Pill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.pillPalBlue)

                        Text("Pal")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.pillPalYellow)
                    }
                    .offset(y: logoOffset)
                    .opacity(logoOpacity)

                    // Subtitle
                    Text("Your medication companion")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .offset(y: logoOffset)
                        .opacity(logoOpacity)
                }
                
                // Buttons Section
                VStack(spacing: 12) {
                    // I Take Medicine Button
                    Button(action: {}) {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                .medicineIconStart,
                                                .medicineIconEnd
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                    .shadow(color: .medicineGlowShadow, radius: 8)

                                Image(systemName: "heart.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text("I Take Medicine")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.8))
                            .shadow(radius: 8)
                    )
                    .opacity(buttonOpacity)
                    
                    // I'm a Caregiver Button
                    Button(action: {}) {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                .caregiverIconStart,
                                                .caregiverIconEnd
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                    .shadow(color: .caregiverGlowShadow, radius: 8)

                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text("I'm a Caregiver")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.8))
                            .shadow(radius: 8)
                    )
                    .opacity(buttonOpacity)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    @State private var animatingGlow = false
    
    private func startAnimations() {
        // Logo fade in
        withAnimation(.easeOut(duration: 0.8)) {
            logoOpacity = 1.0
        }
        
        // Logo glide up after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.8)) {
                logoOffset = 0
                showButtons = true
            }
        }
        
        // Buttons fade in after logo animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.8)) {
                buttonOpacity = 1.0
            }
        }
        
        // Glow animation loop
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            animatingGlow = true
        }
    }
}

#Preview {
    LandingView()
}
