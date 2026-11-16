import Foundation

nonisolated struct TrackingParameterCleaner: Sendable {
    static let defaultTrackerParameters: Set<String> = [

        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_term",
        "utm_content",
        "utm_id",
        "utm_source_platform",
        "utm_creative_format",
        "utm_marketing_tactic",

        "fbclid",

        "gclid",
        "gbraid",
        "wbraid",
        "_ga",
        "_gl",

        "twclid",

        "ttclid",

        "msclkid",

        "si",

        "igshid",

        "mc_cid",
        "mc_eid",

        "yclid",

        "wickedid",
        "ref",
        "ref_src",
        "ref_url",
        "aff_id"
    ]

    static func clean(url: URL, trackerParams: Set<String> = defaultTrackerParameters) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }

        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return url
        }

        let filtered = queryItems.filter { item in
            let key = item.name.lowercased()
            return !trackerParams.contains(key)
        }

        if filtered.isEmpty {
            components.queryItems = nil

            if components.query?.isEmpty == true {
                components.query = nil
            }
        } else {
            components.queryItems = filtered
        }

        return components.url ?? url
    }

    static func clean(urlString: String, trackerParams: Set<String> = defaultTrackerParameters) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return clean(url: url, trackerParams: trackerParams).absoluteString
    }
}
