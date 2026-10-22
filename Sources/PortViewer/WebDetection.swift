import Foundation

/// Recognizes common frontend / dev servers from a process's argv.
enum DevServerDetector {
    /// Checked in order, so frameworks that run on top of Vite or Webpack come first.
    private static let rules: [(name: String, pattern: String)] = [
        ("Next.js", tool("next", "next-server", "next-router-worker")),
        ("Nuxt", tool("nuxt", "nuxi")),
        ("Astro", tool("astro")),
        ("SvelteKit", tool("svelte-kit")),
        ("Remix", tool("remix")),
        ("Gatsby", tool("gatsby")),
        ("Docusaurus", tool("docusaurus")),
        ("Storybook", tool("storybook", "start-storybook")),
        ("Expo", tool("expo")),
        ("Angular", tool("ng") + #".*\sserve\b"#),
        ("Create React App", tool("react-scripts")),
        ("Vite", tool("vite")),
        ("Webpack", tool("webpack", "webpack-dev-server")),
        ("Parcel", tool("parcel")),
        ("Eleventy", tool("eleventy")),
        ("Hugo", tool("hugo") + #".*\sserver\b"#),
        ("Jekyll", tool("jekyll") + #".*\sserve\b"#),
        ("Django", #"manage\.py\s+runserver"#),
        ("Rails", tool("rails") + #"\s+s(erver)?\b"#),
        ("PHP", tool("php") + #"\s+-S\b"#),
        ("Python HTTP", #"-m\s+http\.server"#),
        ("Live Server", tool("live-server", "http-server", "serve")),
    ]

    /// Matches a tool name as a whole argv token or path component, e.g. "vite",
    /// "node_modules/.bin/vite" or "vite/bin/vite.js".
    private static func tool(_ names: String...) -> String {
        let alternatives = names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return #"(?:^|[\s/])(?:"# + alternatives + #")(?:\.(?:js|mjs|cjs))?(?=$|[\s/])"#
    }

    private static let compiled: [(String, NSRegularExpression)] = rules.compactMap { rule in
        (try? NSRegularExpression(pattern: rule.pattern)).map { (rule.name, $0) }
    }

    static func framework(for arguments: [String]) -> String? {
        let commandLine = arguments.joined(separator: " ")
        let range = NSRange(commandLine.startIndex..., in: commandLine)
        return compiled.first { $0.1.firstMatch(in: commandLine, range: range) != nil }?.0
    }
}

/// Checks whether a port serves an HTML page, i.e. something worth opening in a browser.
enum WebProbe {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func servesHTML(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return contentType.contains("text/html") && http.statusCode < 500
    }
}
