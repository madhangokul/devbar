struct VercelProvider: ToolbarProvider {
    let id = "vercel"
    let displayName = "Vercel"
    let iconSystemName = "triangle.fill"
    let credentialFields = [
        CredentialField(
            key: "token",
            label: "Access token",
            placeholder: "Vercel personal access token",
            isSecret: true,
            isRequired: true
        ),
        CredentialField(
            key: "teamId",
            label: "Team ID",
            placeholder: "Optional",
            isSecret: false,
            isRequired: false
        )
    ]

    func fetchItems(credentials: [String: String]) async throws -> [ToolbarItem] {
        guard let token = credentials["token"], !token.isEmpty else {
            throw VercelError.missingToken
        }
        return try await VercelAPIClient(token: token, teamId: credentials["teamId"]).fetchItems()
    }
}
