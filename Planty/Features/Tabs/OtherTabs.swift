import SwiftUI

// Discover, Calendar and Achievements get their content in Steps 4 and 5.
// Until then each tab shows a clear empty state and no controls that do nothing.

struct DiscoverView: View {
    var body: some View {
        ScrollView {
            PlantyEmptyState(
                title: "The plant encyclopedia is growing",
                message: "Care guides for popular houseplants, written from trusted sources, will appear here."
            ) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.plantySage)
                    .accessibilityHidden(true)
            }
            .padding(.top, PlantySpacing.xl)
        }
        .plantyScreenBackground()
        .navigationTitle("Discover")
    }
}

struct CareCalendarView: View {
    var body: some View {
        ScrollView {
            PlantyEmptyState(
                title: "No care tasks yet",
                message: "Once you add plants, watering, feeding and check-ups will show up here by day and week."
            ) {
                Image(systemName: "calendar")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.plantySage)
                    .accessibilityHidden(true)
            }
            .padding(.top, PlantySpacing.xl)
        }
        .plantyScreenBackground()
        .navigationTitle("Care calendar")
    }
}

struct AchievementsView: View {
    var body: some View {
        ScrollView {
            PlantyEmptyState(
                title: "Your first award is close",
                message: "Add your first plant to unlock it. Awards reward a steady care routine, never extra watering."
            ) {
                Image(systemName: "trophy")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.plantyWarning)
                    .accessibilityHidden(true)
            }
            .padding(.top, PlantySpacing.xl)
        }
        .plantyScreenBackground()
        .navigationTitle("Achievements")
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                HStack(spacing: PlantySpacing.m) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.plantySage)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let user = session.user, user.isGuest {
                            Text("Guest").font(.plantyHeadline)
                            Text("Your garden is saved to this guest account only.")
                                .font(.plantyCaption)
                                .foregroundStyle(Color.plantyTextSecondary)
                        } else {
                            Text(verbatim: session.user?.email ?? "").font(.plantyHeadline)
                            Text("Free plan").font(.plantyCaption).foregroundStyle(Color.plantyTextSecondary)
                        }
                    }
                }
                .padding(.vertical, PlantySpacing.xs)
            }

            Section("Settings") {
                Button("Language and notifications") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }

            Section {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }

            if let error = session.lastError {
                Section { Text(error).foregroundStyle(Color.plantyCritical) }
            }
        }
        .scrollContentBackground(.hidden)
        .plantyScreenBackground()
        .navigationTitle("Profile")
        .confirmationDialog("Sign out of Planty?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
        } message: {
            if session.user?.isGuest == true {
                Text("You are a guest. If you sign out, you can't get this garden back.")
            }
        }
    }
}
