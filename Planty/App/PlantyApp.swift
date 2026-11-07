import Supabase
import SwiftUI

@main
struct PlantyApp: App {
    @State private var session: SessionStore?
    @State private var configurationError: String?

    init() {
        do {
            let client = try SupabaseBackend.makeClient()
            _session = State(initialValue: SessionStore(
                auth: SupabaseAuthService(client: client),
                profiles: SupabaseProfileRepository(client: client)
            ))
        } catch {
            _configurationError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    RootView()
                        .environment(session)
                } else {
                    PlantyEmptyState(
                        title: "Planty can't start",
                        message: LocalizedStringKey(configurationError ?? "")
                    ) { EmptyView() }
                    .frame(maxHeight: .infinity)
                    .plantyScreenBackground()
                }
            }
            .tint(.plantyForest)
        }
    }
}
