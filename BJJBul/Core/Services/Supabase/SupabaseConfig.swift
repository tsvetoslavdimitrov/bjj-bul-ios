import Foundation
import Supabase

enum SupabaseConfig {
    /// Reads values injected from Config/Secrets.xcconfig via Info.plist. Returns nil if missing.
    static func makeClient(bundle: Bundle = .main) -> SupabaseClient? {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let url = URL(string: urlString),
            !key.isEmpty, !key.contains("REPLACE_ME")
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }
}
