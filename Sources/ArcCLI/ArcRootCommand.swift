import ArgumentParser

/// Root command for the `arc` tool.
///
/// This is the interface layer (argument parsing + command routing).
public struct ArcRootCommand: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "arc",
        abstract: "Arc - Server Management Tool",
        version: "1.0.0",
        subcommands: [
            InitializeCommand.self,
            StartCommand.self,
            StopCommand.self,
            StatusCommand.self,
            LogsCommand.self,
        ]
    )
}
