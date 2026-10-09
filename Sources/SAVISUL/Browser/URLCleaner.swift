import Foundation

/// The same tracker stripping the browser notch applies to a link.
enum URLCleaner {
    struct Clean: Equatable {
        var url: String
        var removed: Int
    }

    static func clean(_ href: String) -> Clean {
        guard var parts = URLComponents(string: href),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return Clean(url: href, removed: 0)
        }
        let host = (parts.host ?? "").lowercased()
        var removed = 0
        if var items = parts.queryItems {
            let kept = items.filter { !isTracker($0.name, host: host) }
            removed += items.count - kept.count
            items = kept
            parts.queryItems = items.isEmpty ? nil : items
        }
        if host.range(of: amazon, options: .regularExpression) != nil {
            let path = parts.path.removingPercentEncoding ?? parts.path
            let stripped = path.replacingOccurrences(of: #"/ref=[^/]*$"#, with: "", options: .regularExpression)
            if stripped != path {
                parts.path = stripped
                removed += 1
            }
        }
        if let fragment = parts.fragment, fragment.hasPrefix(":~:") || fragment.lowercased().hasPrefix("utm_") {
            parts.fragment = nil
            removed += 1
        }
        var result = parts.string ?? href
        if parts.queryItems == nil, result.hasSuffix("?"), parts.fragment == nil {
            result.removeLast()
        }
        return Clean(url: result, removed: removed)
    }

    static func normalize(_ href: String) -> String {
        let cleaned = clean(href).url
        guard var parts = URLComponents(string: cleaned), let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return href }
        var path = parts.path
        if path.count > 1 { while path.hasSuffix("/") { path.removeLast() } }
        parts.path = path
        parts.host = parts.host?.lowercased()
        if let fragment = parts.fragment, !(fragment.hasPrefix("!") || fragment.hasPrefix("/")) {
            parts.fragment = nil
        }
        return parts.string ?? href
    }

    static func host(of href: String) -> String {
        guard let host = URL(string: href)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isTracker(_ name: String, host: String) -> Bool {
        let key = name.lowercased()
        let site = host.lowercased()
        if anywhere.contains(key) {
            if key != "si" { return true }
            return siHosts.contains { site == $0 || site.hasSuffix("." + $0) }
        }
        if prefixes.contains(where: { key.hasPrefix($0) }) { return true }
        return bySite.contains { pattern, keys in
            site.range(of: pattern, options: .regularExpression) != nil && keys.contains(key)
        }
    }

    private static let prefixes = ["utm_", "pk_", "mtm_", "hsa_", "ga_", "_hs", "oly_", "vero_", "trk_", "aff_", "at_", "sc_", "wt_", "pd_rd_", "pf_rd_"]
    private static let anywhere: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "ysclid", "_openstat", "igshid", "igsh",
        "mc_cid", "mc_eid", "mkt_tok", "rb_clickid", "s_cid", "wickedid", "twclid", "ttclid", "li_fat_id", "epik", "srsltid",
        "ref_src", "ref_url", "_ga", "_gl", "cmpid", "zanpid", "xtor", "irclickid", "admitad_uid", "tduid", "awc", "obclid",
        "dicbo", "_branch_match_id", "_bta_tid", "_bta_c", "mbid", "soc_src", "soc_trk", "mibextid", "__cft__", "__tn__",
        "hsctatracking", "spm", "scm", "share_id", "si"
    ]
    private static let siHosts = ["youtube.com", "youtu.be", "spotify.com", "instagram.com"]
    private static let amazon = #"(^|\.)amazon\.[a-z.]+$"#
    private static let bySite: [(String, Set<String>)] = [
        (#"(^|\.)google\.[a-z.]+$"#, ["ved", "ei", "oq", "sxsrf", "sca_esv", "gs_lcrp", "gs_lp", "uact", "aqs", "sourceid", "sclient", "iflsig", "rlz", "bih", "biw"]),
        (#"(^|\.)bing\.com$"#, ["form", "sk", "sp", "cvid", "qs", "sc", "pq", "ghsh", "ghacc", "ghpl"]),
        (#"(^|\.)amazon\.[a-z.]+$"#, ["_encoding", "psc", "refrid", "qid", "sr", "dib", "dib_tag", "content-id", "ascsubtag", "linkcode", "creativeasin", "smid", "th", "sprefix", "crid", "ref", "tag"]),
        (#"(^|\.)(youtube\.com|youtu\.be)$"#, ["feature", "pp", "embeds_referring_euri", "source_ve_path", "ab_channel"]),
        (#"(^|\.)(twitter\.com|x\.com)$"#, ["s", "t"]),
        (#"(^|\.)facebook\.com$"#, ["ref", "rdid", "refsrc", "hc_ref", "fref"]),
        (#"(^|\.)yandex\.[a-z.]+$"#, ["suggest_reqid", "from"])
    ]
}
