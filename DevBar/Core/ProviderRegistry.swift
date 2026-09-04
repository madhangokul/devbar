enum ProviderRegistry {
    // Adding a provider only requires registering its implementation here.
    static let all: [any ToolbarProvider] = [
        VercelProvider()
    ]
}
