import CascadeKit
import Testing
@testable import CLIKit

struct ShoutingGreeter: Greeter {
    func greeting(for name: String) -> String {
        name.uppercased()
    }
}

@Test
func greetUsesOverriddenGreeter() throws {
    let message = try withTestDependencies { $0.greeter = ShoutingGreeter() } operation: {
        try Actions().greet(name: " ada ")
    }
    #expect(message == "ADA")
}

@Test
func greetUsesTestValueByDefault() throws {
    let message = try withTestDependencies { try Actions().greet(name: "bob") }
    #expect(message == "greeting:bob")
}

@Test
func greetRejectsEmptyName() {
    #expect(throws: CLIError.emptyName) {
        try withTestDependencies { try Actions().greet(name: "  ") }
    }
}

@Test
func statusUsesFixedService() {
    #expect(withTestDependencies { Actions().status() } == "ok, up 0s")
}

@Test
func runInAppResolvesRegisteredStatusService() async {
    let summary = await runInApp { Actions().status() }
    #expect(summary.hasPrefix("ok, up"))
}
