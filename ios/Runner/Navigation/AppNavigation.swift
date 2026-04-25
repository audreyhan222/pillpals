import SwiftUI

enum AppScreen: Hashable {
    case landing
    case medicineTracker
    case caregiverDashboard
    case home
}

struct AppNavigationView: View {
    @State private var navigationPath: NavigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            LandingView()
                .navigationDestination(for: AppScreen.self) { screen in
                    switch screen {
                    case .landing:
                        LandingView()
                    case .medicineTracker:
                        // TODO: Create MedicineTrackerView
                        Text("Medicine Tracker")
                    case .caregiverDashboard:
                        // TODO: Create CaregiverDashboardView
                        Text("Caregiver Dashboard")
                    case .home:
                        // TODO: Create HomeView
                        Text("Home")
                    }
                }
        }
    }
}

#Preview {
    AppNavigationView()
}
