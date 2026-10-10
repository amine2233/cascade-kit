import ArgumentParser
import CLIKit

@main
struct Cascade: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cascade-cli",
        version: "1.0.0",
        subcommands: [Greet.self, Status.self]
    )
}

struct Greet: AsyncParsableCommand {
    @Argument(help: "Who to greet.") var name: String

    func run() async throws {
        let message = try await runInApp { try Actions().greet(name: name) }
        print(message)
    }
}

struct Status: AsyncParsableCommand {
    func run() async {
        await print(runInApp { Actions().status() })
    }
}
