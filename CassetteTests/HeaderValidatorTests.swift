import Testing
@testable import Cassette

@Suite("HeaderValidator")
struct HeaderValidatorTests {

    // MARK: - isValidName — valid

    @Test func validName_commonHeaders() {
        #expect(HeaderValidator.isValidName("Authorization"))
        #expect(HeaderValidator.isValidName("content-type"))
        #expect(HeaderValidator.isValidName("X-Request-Id"))
        #expect(HeaderValidator.isValidName("CF-Access-Client-Id"))
        #expect(HeaderValidator.isValidName("x123"))
    }

    @Test func validName_allTcharSymbols() {
        // Every non-alphanumeric tchar from RFC 7230 §3.2.6
        for ch in ["!", "#", "$", "%", "&", "'", "*", "+", "-", ".", "^", "_", "`", "|", "~"] {
            #expect(HeaderValidator.isValidName("a\(ch)b"), "tchar '\(ch)' should be valid")
        }
    }

    // MARK: - isValidName — invalid

    @Test func invalidName_empty() {
        #expect(!HeaderValidator.isValidName(""))
    }

    @Test func invalidName_space() {
        #expect(!HeaderValidator.isValidName("My Header"))
    }

    @Test func invalidName_colon() {
        // Colon is the name/value separator in HTTP — not a tchar
        #expect(!HeaderValidator.isValidName("Host:"))
    }

    @Test func invalidName_atSign() {
        #expect(!HeaderValidator.isValidName("user@host"))
    }

    @Test func invalidName_nonASCII() {
        #expect(!HeaderValidator.isValidName("Héader"))
        #expect(!HeaderValidator.isValidName("头部"))
    }

    @Test func invalidName_controlCharacters() {
        #expect(!HeaderValidator.isValidName("header\r"))
        #expect(!HeaderValidator.isValidName("header\n"))
        #expect(!HeaderValidator.isValidName("header\0"))
    }

    // MARK: - isValidValue — valid

    @Test func validValue_empty() {
        // Empty value is allowed by RFC 7230
        #expect(HeaderValidator.isValidValue(""))
    }

    @Test func validValue_normalStrings() {
        #expect(HeaderValidator.isValidValue("Bearer eyJhbGciOiJSUzI1NiJ9"))
        #expect(HeaderValidator.isValidValue("application/json; charset=utf-8"))
        #expect(HeaderValidator.isValidValue("no-cache, no-store"))
    }

    @Test func validValue_whitespace() {
        #expect(HeaderValidator.isValidValue("value with spaces"))
        #expect(HeaderValidator.isValidValue("value\twith\ttabs"))
    }

    // MARK: - isValidValue — invalid

    @Test func invalidValue_carriageReturn() {
        #expect(!HeaderValidator.isValidValue("value\r"))
        #expect(!HeaderValidator.isValidValue("\rleading"))
    }

    @Test func invalidValue_lineFeed() {
        #expect(!HeaderValidator.isValidValue("value\n"))
        #expect(!HeaderValidator.isValidValue("\nleading"))
    }

    @Test func invalidValue_nul() {
        #expect(!HeaderValidator.isValidValue("value\0"))
    }

    @Test func invalidValue_headerSplittingAttempt() {
        // Classic header injection — must be rejected
        #expect(!HeaderValidator.isValidValue("legit\r\nInjected: evil"))
        #expect(!HeaderValidator.isValidValue("ok\nSet-Cookie: session=hijacked"))
    }
}
