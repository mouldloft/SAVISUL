import Testing
@testable import SAVISUL

@Test func trackingParametersGoAndTheQueryStays() {
    let cleaned = URLCleaner.clean("https://example.com/a?id=7&utm_source=news&utm_medium=email")
    #expect(cleaned.removed == 2)
    #expect(!cleaned.url.contains("utm_"))
    #expect(cleaned.url.contains("id=7"))
}

@Test func clickIdentifiersGoOnAnySite() {
    let cleaned = URLCleaner.clean("https://shop.test/item?fbclid=abc&gclid=def&color=red")
    #expect(cleaned.removed == 2)
    #expect(cleaned.url.contains("color=red"))
    #expect(!cleaned.url.contains("fbclid"))
}

@Test func aRealQueryIsKept() {
    let cleaned = URLCleaner.clean("https://example.com/search?q=savisul")
    #expect(cleaned.removed == 0)
    #expect(cleaned.url.contains("q=savisul"))
}

@Test func nonWebURLsAreUntouched() {
    #expect(URLCleaner.clean("mailto:hi@example.com?subject=Hi").removed == 0)
    #expect(URLCleaner.clean("not a url").removed == 0)
    #expect(URLCleaner.clean("").url == "")
    #expect(URLCleaner.clean("ftp://files.example.com/a?utm_source=x").removed == 0)
}

@Test func amazonTagAndRefPath() {
    let cleaned = URLCleaner.clean("https://www.amazon.com/dp/B00TEST/ref=sr_1_1?tag=savisul-20&psc=1")
    #expect(cleaned.removed >= 2)
    #expect(!cleaned.url.contains("tag="))
    #expect(!cleaned.url.contains("/ref="))
    #expect(cleaned.url.contains("/dp/B00TEST"))
}

@Test func googleNoiseGoes() {
    let cleaned = URLCleaner.clean("https://www.google.com/search?q=savisul&ved=abc&ei=xyz")
    #expect(!cleaned.url.contains("ved="))
    #expect(!cleaned.url.contains("ei="))
    #expect(cleaned.url.contains("q=savisul"))
}

@Test func siOnlyOnSomeHosts() {
    #expect(URLCleaner.isTracker("si", host: "youtube.com"))
    #expect(URLCleaner.isTracker("si", host: "open.spotify.com"))
    #expect(!URLCleaner.isTracker("si", host: "example.com"))
    #expect(URLCleaner.isTracker("UTM_Source", host: "example.com"))
}

@Test func hashes() {
    #expect(!URLCleaner.clean("https://example.com/doc#utm_source=x").url.contains("#"))
    #expect(!URLCleaner.clean("https://example.com/doc#:~:text=hello").url.contains("#"))
    #expect(URLCleaner.clean("https://example.com/doc#install").url.contains("#install"))
}

@Test func normalizeAndHost() {
    let normalized = URLCleaner.normalize("HTTPS://WWW.Example.com/path/?utm_source=a")
    #expect(normalized.lowercased().contains("example.com/path"))
    #expect(!normalized.contains("utm_"))
    #expect(URLCleaner.host(of: "https://www.example.com/a") == "example.com")
    #expect(URLCleaner.host(of: "not a url") == "")
    #expect(URLCleaner.normalize("https://app.example.com/#/inbox").contains("#/inbox"))
}
