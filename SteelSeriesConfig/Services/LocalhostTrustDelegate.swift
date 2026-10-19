import Foundation

/// Grants TLS trust to the engine's self-signed certificate — but only to loopback.
///
/// The engine serves `O=SteelSeries ApS` self-signed TLS on `127.0.0.1:50530`.
/// Accepting that certificate is required to talk to it at all; accepting it
/// *anywhere* would be a credential-theft vector, because anything able to redirect
/// the app to another host would then pass verification. So the exception is scoped
/// to the exact host and port discovered from `coreProps.json`, and any other host
/// fails closed.
final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let allowedHost: String
    private let allowedPort: Int?

    init(allowedHost: String, allowedPort: Int?) {
        self.allowedHost = allowedHost
        self.allowedPort = allowedPort
    }

    convenience init(engineURL: URL) {
        self.init(allowedHost: engineURL.host ?? "127.0.0.1", allowedPort: engineURL.port)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            // Anything that is not server-trust validation (credentials, client
            // certificates) gets no special treatment — the engine never asks.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let space = challenge.protectionSpace
        let hostMatches = space.host == allowedHost
        let portMatches = (allowedPort == nil || space.port == allowedPort)

        if hostMatches && portMatches {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
