import XCTest
@testable import DaktRecorder

final class CorporateProxyProfileTests: XCTestCase {
    func testUsesTheExplicitlySelectedHTTPSProxyWithoutAHardcodedOrganization() throws {
        let config = """
        model_provider = "work"
        [model_providers.work]
        base_url = "https://proxy.example/direct/codex/v1"
        http_headers = { "X-Proxy-Token" = "test-proxy" }
        """
        let auth = Data(#"{"tokens":{"access_token":"test-key","account_id":"test-account"}}"#.utf8)
        let result = try CorporateProxyProfile.parse(config: config, auth: auth)
        XCTAssertEqual(result.endpoint, "https://proxy.example/direct/codex/v1/responses")
        XCTAssertEqual(result.proxyToken, "test-proxy")
    }

    private let auth = Data(#"{"tokens":{"access_token":"test-access","account_id":"test-account"}}"#.utf8)

    func testLoadsOnlySelectedCorporateProviderAndInlineHeader() throws {
        let text = """
        model_provider = "work"
        [model_providers.work]
        base_url = "https://proxy.example/direct/codex/v1"
        http_headers = { "X-Proxy-Token" = "test-proxy" }
        [unrelated]
        base_url = "https://other.example"
        """
        let result = try CorporateProxyProfile.parse(config: text, auth: auth)
        XCTAssertEqual(result.endpoint, "https://proxy.example/direct/codex/v1/responses")
        XCTAssertEqual(result.proxyToken, "test-proxy")
        XCTAssertEqual(result.apiKey, "test-access")
        XCTAssertEqual(result.accountID, "test-account")
    }

    func testRejectsUnselectedProviderBeforeUsingLogin() {
        let text = """
        model_provider = "missing"
        [model_providers.work]
        base_url = "https://unrelated.example/v1"
        http_headers = { "X-Proxy-Token" = "test-proxy" }
        """
        XCTAssertThrowsError(try CorporateProxyProfile.parse(config: text, auth: auth))
    }

    func testAcceptsHeaderTableAndAPIKey() throws {
        let text = """
        model_provider = 'work'
        [model_providers.work]
        base_url = 'https://proxy.example/direct/openai/v1/'
        [model_providers.work.http_headers]
        X-Proxy-Token = 'test-proxy'
        """
        let result = try CorporateProxyProfile.parse(config: text, auth: Data(#"{"OPENAI_API_KEY":"test-key"}"#.utf8))
        XCTAssertEqual(result.apiKey, "test-key")
        XCTAssertEqual(result.endpoint, "https://proxy.example/direct/openai/v1/responses")
    }

    func testRejectsInsecureOrCredentialBearingProxyURLs() {
        for base in ["http://proxy.example/v1", "https://user:password@proxy.example/v1",
                     "https://proxy.example/v1?token=example", "https://proxy.example/v1#fragment"] {
            let config = """
            model_provider = "work"
            [model_providers.work]
            base_url = "\(base)"
            http_headers = { "X-Proxy-Token" = "test-proxy" }
            """
            XCTAssertThrowsError(try CorporateProxyProfile.parse(config: config, auth: auth))
        }
    }
}
