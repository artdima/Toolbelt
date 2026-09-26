import Foundation
import Testing
@testable import ToolbeltCore

@Suite("JSON pretty-printing")
struct JSONPrettyTests {
    @Test("Nested containers are indented, empty ones stay compact")
    func nested() {
        let compact = #"{"z":1,"a":{"b":[1,2,{}],"c":[]},"s":"x, {y}: \"q\""}"#
        let expected = """
        {
          "z": 1,
          "a": {
            "b": [
              1,
              2,
              {}
            ],
            "c": []
          },
          "s": "x, {y}: \\"q\\""
        }
        """
        #expect(JSONPretty.format(compact) == expected)
    }

    @Test("Key order is kept and existing whitespace is dropped")
    func keyOrder() {
        #expect(JSONPretty.format("{ \"z\" : 1 ,\n \"a\" : true }") == "{\n  \"z\": 1,\n  \"a\": true\n}")
    }

    @Test("Scalars pass through, anything else is nil")
    func edges() {
        #expect(JSONPretty.format("42") == "42")
        #expect(JSONPretty.format(#"{"a":}"#) == nil)
        #expect(JSONPretty.format("<html>") == nil)
        #expect(JSONPretty.format("") == nil)
    }
}
