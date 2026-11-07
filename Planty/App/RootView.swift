import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .plantyScreenBackground()
            case .signedOut:
                WelcomeView()
            case .onboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            case .failed(let message):
                PlantyEmptyState(title: "Planty can't start", message: LocalizedStringKey(message)) { EmptyView() }
                    .frame(maxHeight: .infinity)
                    .plantyScreenBackground()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .task { await session.start() }
    }
}

enum AppTab: Hashable {
    case garden, discover, calendar, achievements, profile
}

struct MainTabView: View {
    @State private var selection: AppTab = .garden

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { GardenView() }
                .tabItem { Label("Garden", systemImage: "leaf") }
                .tag(AppTab.garden)
            NavigationStack { DiscoverView() }
                .tabItem { Label("Discover", systemImage: "safari") }
                .tag(AppTab.discover)
            NavigationStack { CareCalendarView() }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            NavigationStack { AchievementsView() }
                .tabItem { Label("Awards", systemImage: "trophy") }
                .tag(AppTab.achievements)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}
