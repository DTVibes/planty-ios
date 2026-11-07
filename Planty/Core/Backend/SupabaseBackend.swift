import Foundation
import Supabase

/// Reads the Supabase project settings that Config/Planty.xcconfig puts into Info.plist.
/// Only the public URL and the publishable key ship with the app; Row Level Security
/// protects the data. Secret keys live in Supabase Edge Function secrets, never here.
enum BackendConfig {
    struct Missing: LocalizedError {
        var errorDescription: String? { "Supabase is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Config/Planty.xcconfig." }
    }

    static func load(bundle: Bundle = .main) throws -> (url: URL, key: String) {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: urlString), url.scheme == "https",
            let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
            !key.isEmpty, !key.hasPrefix("$(")
        else { throw Missing() }
        return (url, key)
    }
}

enum SupabaseBackend {
    static func makeClient() throws -> SupabaseClient {
        let config = try BackendConfig.load()
        return SupabaseClient(supabaseURL: config.url, supabaseKey: config.key)
    }
}
