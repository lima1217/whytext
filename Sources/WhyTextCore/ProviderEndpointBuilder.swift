import Foundation

public enum ProviderEndpointBuilder {
    public enum Error: Swift.Error, Equatable {
        case invalidBaseURL
    }

    public static func endpointURL(baseURL: String, resourcePath: String) throws -> URL {
        let rawBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBaseURL.isEmpty else { throw Error.invalidBaseURL }

        let base = rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedBase = base.lowercased()

        if isCompleteEndpoint(lowercasedBase) {
            guard let url = URL(string: base) else {
                throw Error.invalidBaseURL
            }
            return url
        }

        let path: String
        if hasVersionedPathSuffix(base) {
            path = resourcePath
        } else {
            path = "v1/\(resourcePath)"
        }

        let urlString = "\(base)/\(path)"
        guard let url = URL(string: urlString) else {
            throw Error.invalidBaseURL
        }

        return url
    }

    private static func isCompleteEndpoint(_ lowercasedBase: String) -> Bool {
        lowercasedBase.hasSuffix("/chat/completions")
            || lowercasedBase.hasSuffix("/responses")
    }

    private static func hasVersionedPathSuffix(_ base: String) -> Bool {
        guard let url = URL(string: base),
              let lastComponent = url.pathComponents.last?.lowercased(),
              lastComponent.count >= 2,
              lastComponent.first == "v" else {
            return false
        }

        return lastComponent.dropFirst().allSatisfy(\.isNumber)
    }
}
