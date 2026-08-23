//
//  GoogleDriveClient.swift
//  Aidoku
//
//  Created by Amqx on 8/20/26.
//

import CryptoKit
import Foundation

/// Client for storing backups in a folder in the user's Google Drive.
///
/// Uses the OAuth 2.0 flow for installed apps (PKCE, no client secret) and the `drive.file` scope,
/// which only grants access to files this app creates.
actor GoogleDriveClient {
    static let shared = GoogleDriveClient()

    /// The iOS OAuth client id from the Google Cloud project, ending in `.apps.googleusercontent.com`.
    ///
    /// Leave empty to disable Google Drive backups entirely.
    static let clientId = "180221226170-5cd6d3obdirnq9urlq1b02q8p2q7hocp.apps.googleusercontent.com"

    static let folderName = "Aidoku Backups"

    static let enabledKey = "AutomaticBackups.googleDrive.enabled"
    static let lastUploadKey = "AutomaticBackups.googleDrive.lastUpload"

    // contains "auth"/"token", so these are stripped from backups unless sensitive settings are included
    private static let tokensKey = "AutomaticBackups.googleDrive.oauth"
    private static let accountKey = "AutomaticBackups.googleDrive.tokenAccount"
    private static let folderIdKey = "AutomaticBackups.googleDrive.folderId"

    /// Keys that are tied to this device's sign in, so they shouldn't come along in a backup.
    static let excludedSettingsKeys = [enabledKey, lastUploadKey, folderIdKey, accountKey]

    private static let authorizeUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenUrl = "https://oauth2.googleapis.com/token"
    private static let revokeUrl = "https://oauth2.googleapis.com/revoke"
    private static let apiUrl = "https://www.googleapis.com/drive/v3"
    private static let uploadUrl = "https://www.googleapis.com/upload/drive/v3/files"
    private static let scope = "https://www.googleapis.com/auth/drive.file"

    // google recommends resumable uploads above 5 mb
    private static let multipartUploadLimit = 5 * 1024 * 1024

    static var isConfigured: Bool {
        !clientId.isEmpty
    }

    /// Google requires installed apps to redirect to a scheme in reverse dns notation. For ios
    /// clients that's the client id with its components reversed.
    static var callbackScheme: String {
        clientId
            .components(separatedBy: ".")
            .reversed()
            .joined(separator: ".")
    }

    private static var redirectUri: String {
        callbackScheme + ":/oauth2redirect"
    }

    enum GoogleDriveError: Error {
        case notConfigured
        case notSignedIn
        case authenticationFailed
        case badResponse
        case http(status: Int, message: String)
    }

    private var tokens: OAuthResponse?
    private var codeVerifier = ""

    var isSignedIn: Bool {
        loadTokens()
        return tokens?.refreshToken != nil
    }

    /// The email address of the signed in account, if it could be fetched.
    var account: String? {
        UserDefaults.standard.string(forKey: Self.accountKey)
    }
}

// MARK: - Authentication
extension GoogleDriveClient {
    func authenticationUrl() -> URL? {
        guard Self.isConfigured, var components = URLComponents(string: Self.authorizeUrl) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: generatePkceChallenge()),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // required in order to receive a refresh token
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url
    }

    func handleAuthenticationCallback(url: URL) async throws {
        guard Self.isConfigured else { throw GoogleDriveError.notConfigured }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleDriveError.authenticationFailed
        }

        let response: OAuthResponse? = try? await sendTokenRequest(body: [
            "grant_type": "authorization_code",
            "client_id": Self.clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": Self.redirectUri
        ])
        guard let response, response.refreshToken != nil else {
            throw GoogleDriveError.authenticationFailed
        }
        setTokens(response)

        // best effort, the account is only used to label the sign in row
        UserDefaults.standard.set(try? await fetchAccountEmail(), forKey: Self.accountKey)
    }

    func signOut() async {
        loadTokens()
        if let token = tokens?.refreshToken ?? tokens?.accessToken, var components = URLComponents(string: Self.revokeUrl) {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
            if let url = components.url {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        clearTokens()
    }

    private func clearTokens() {
        tokens = nil
        UserDefaults.standard.removeObject(forKey: Self.tokensKey)
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        UserDefaults.standard.removeObject(forKey: Self.folderIdKey)
        UserDefaults.standard.removeObject(forKey: Self.lastUploadKey)
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    private func loadTokens() {
        guard tokens == nil else { return }
        if let data = UserDefaults.standard.data(forKey: Self.tokensKey) {
            tokens = try? JSONDecoder().decode(OAuthResponse.self, from: data)
        }
    }

    private func setTokens(_ response: OAuthResponse) {
        var response = response
        // google omits the refresh token when refreshing, so keep the one we already have
        if response.refreshToken == nil {
            response.refreshToken = tokens?.refreshToken
        }
        tokens = response
        UserDefaults.standard.set(try? JSONEncoder().encode(response), forKey: Self.tokensKey)
    }

    private func refreshAccessToken() async throws {
        loadTokens()
        guard let refreshToken = tokens?.refreshToken else { throw GoogleDriveError.notSignedIn }
        do {
            let response: OAuthResponse = try await sendTokenRequest(body: [
                "grant_type": "refresh_token",
                "client_id": Self.clientId,
                "refresh_token": refreshToken
            ])
            setTokens(response)
        } catch GoogleDriveError.http(let status, _) where status == 400 || status == 401 {
            // the refresh token was revoked or expired, so signing in again is the only way back
            clearTokens()
            throw GoogleDriveError.notSignedIn
        }
    }

    private func sendTokenRequest(body: [String: String]) async throws -> OAuthResponse {
        guard let url = URL(string: Self.tokenUrl) else { throw GoogleDriveError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.percentEncoded()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        guard let result = try? JSONDecoder().decode(OAuthResponse.self, from: data) else {
            throw GoogleDriveError.badResponse
        }
        return result
    }

    private func fetchAccountEmail() async throws -> String? {
        guard let url = URL(string: Self.apiUrl + "/about?fields=user(emailAddress)") else { return nil }
        let (data, _) = try await send(URLRequest(url: url))
        struct AboutResponse: Codable {
            struct User: Codable {
                let emailAddress: String?
            }
            let user: User?
        }
        return (try? JSONDecoder().decode(AboutResponse.self, from: data))?.user?.emailAddress
    }
}

// MARK: - Requests
extension GoogleDriveClient {
    /// Performs an authorized request, refreshing the access token once if it was rejected.
    @discardableResult
    private func send(
        _ request: URLRequest,
        fromFile fileUrl: URL? = nil,
        retryUnauthorized: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        guard Self.isConfigured else { throw GoogleDriveError.notConfigured }
        loadTokens()
        guard tokens?.refreshToken != nil else { throw GoogleDriveError.notSignedIn }
        if tokens?.accessToken == nil {
            try await refreshAccessToken()
        }

        var request = request
        request.setValue("Bearer \(tokens?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        // uploading from a file streams it off disk, rather than holding it all in memory
        let (data, response) = if let fileUrl {
            try await URLSession.shared.upload(for: request, fromFile: fileUrl)
        } else {
            try await URLSession.shared.data(for: request)
        }

        if retryUnauthorized, (response as? HTTPURLResponse)?.statusCode == 401 {
            try await refreshAccessToken()
            return try await send(request, fromFile: fileUrl, retryUnauthorized: false)
        }

        try Self.validate(response: response, data: data)
        guard let response = response as? HTTPURLResponse else { throw GoogleDriveError.badResponse }
        return (data, response)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw GoogleDriveError.badResponse }
        guard !(200..<300).contains(response.statusCode) else { return }
        throw GoogleDriveError.http(
            status: response.statusCode,
            message: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - Files
extension GoogleDriveClient {
    private struct DriveFile: Codable {
        let id: String
        let name: String?
        let trashed: Bool?
    }

    private struct DriveFileList: Codable {
        let files: [DriveFile]
    }

    /// Uploads a backup file, skipping it if a file with the same name was already uploaded.
    func upload(backupAt url: URL) async throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let name = url.lastPathComponent
        let folderId = try await folderId()

        let existing = try await listFiles(inFolder: folderId, name: name)
        guard existing.isEmpty else { return }

        if size > Self.multipartUploadLimit {
            // large backups are streamed from disk, since uploads run in a background task
            try await resumableUpload(fileUrl: url, size: size, name: name, folderId: folderId)
        } else {
            try await multipartUpload(data: try Data(contentsOf: url), name: name, folderId: folderId)
        }
    }

    /// Removes all but the newest `keeping` backups from the drive folder.
    func prune(keeping: Int) async throws {
        let folderId = try await folderId()
        guard var components = URLComponents(string: Self.apiUrl + "/files") else { return }
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(folderId)' in parents and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "orderBy", value: "createdTime desc"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components.url else { return }
        let (data, _) = try await send(URLRequest(url: url))
        let files = (try? JSONDecoder().decode(DriveFileList.self, from: data))?.files ?? []

        for file in files.dropFirst(keeping) {
            try await delete(fileId: file.id)
        }
    }

    private func delete(fileId: String) async throws {
        guard let url = URL(string: Self.apiUrl + "/files/" + fileId) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try await send(request)
    }

    private func listFiles(inFolder folderId: String, name: String) async throws -> [DriveFile] {
        guard var components = URLComponents(string: Self.apiUrl + "/files") else { return [] }
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(folderId)' in parents and name = '\(escapedName)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await send(URLRequest(url: url))
        return (try? JSONDecoder().decode(DriveFileList.self, from: data))?.files ?? []
    }

    private func multipartUpload(data: Data, name: String, folderId: String) async throws {
        guard
            let url = URL(string: Self.uploadUrl + "?uploadType=multipart&fields=id"),
            let metadata = Self.metadata(name: name, folderId: folderId)
        else {
            throw GoogleDriveError.badResponse
        }

        let boundary = "aidoku-\(UUID().uuidString)"
        var body = Data()
        body.append(string: "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadata)
        body.append(string: "\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        body.append(string: "\r\n--\(boundary)--")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        try await send(request)
    }

    private func resumableUpload(fileUrl: URL, size: Int, name: String, folderId: String) async throws {
        guard
            let url = URL(string: Self.uploadUrl + "?uploadType=resumable&fields=id"),
            let metadata = Self.metadata(name: name, folderId: folderId)
        else {
            throw GoogleDriveError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = metadata
        let (_, response) = try await send(request)

        guard
            let location = response.value(forHTTPHeaderField: "Location"),
            let sessionUrl = URL(string: location)
        else {
            throw GoogleDriveError.badResponse
        }

        // the whole file is sent in a single chunk, a failure is retried as a new upload
        var uploadRequest = URLRequest(url: sessionUrl)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("bytes 0-\(size - 1)/\(size)", forHTTPHeaderField: "Content-Range")
        try await send(uploadRequest, fromFile: fileUrl)
    }

    private static func metadata(name: String, folderId: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": [folderId]
        ])
    }
}

// MARK: - Folder
extension GoogleDriveClient {
    private static let folderMimeType = "application/vnd.google-apps.folder"

    /// The id of the backup folder, creating it if it doesn't exist yet.
    private func folderId() async throws -> String {
        if
            let storedId = UserDefaults.standard.string(forKey: Self.folderIdKey),
            try await folderExists(id: storedId)
        {
            return storedId
        }
        let id = if let existingId = try await findFolder() {
            existingId
        } else {
            try await createFolder()
        }
        UserDefaults.standard.set(id, forKey: Self.folderIdKey)
        return id
    }

    private func folderExists(id: String) async throws -> Bool {
        guard let url = URL(string: Self.apiUrl + "/files/" + id + "?fields=id,trashed") else { return false }
        do {
            let (data, _) = try await send(URLRequest(url: url))
            let file = try? JSONDecoder().decode(DriveFile.self, from: data)
            return file != nil && file?.trashed != true
        } catch GoogleDriveError.http(let status, _) where status == 404 {
            return false
        }
    }

    private func findFolder() async throws -> String? {
        guard var components = URLComponents(string: Self.apiUrl + "/files") else { return nil }
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "name = '\(Self.folderName)' and mimeType = '\(Self.folderMimeType)' and trashed = false"
            ),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components.url else { return nil }
        let (data, _) = try await send(URLRequest(url: url))
        return (try? JSONDecoder().decode(DriveFileList.self, from: data))?.files.first?.id
    }

    private func createFolder() async throws -> String {
        guard
            let url = URL(string: Self.apiUrl + "/files?fields=id"),
            let body = try? JSONSerialization.data(withJSONObject: [
                "name": Self.folderName,
                "mimeType": Self.folderMimeType
            ])
        else {
            throw GoogleDriveError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await send(request)
        guard let id = (try? JSONDecoder().decode(DriveFile.self, from: data))?.id else {
            throw GoogleDriveError.badResponse
        }
        return id
    }
}

// MARK: - PKCE
private extension GoogleDriveClient {
    func generatePkceChallenge() -> String {
        var octets = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets) == errSecSuccess else {
            return ""
        }
        codeVerifier = Self.base64(octets)
        return codeVerifier
            .data(using: .ascii)
            .map { SHA256.hash(data: $0) }
            .map { Self.base64($0) } ?? ""
    }

    static func base64<S>(_ octets: S) -> String where S: Sequence, UInt8 == S.Element {
        Data(octets)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}

private extension Data {
    mutating func append(string: String) {
        append(Data(string.utf8))
    }
}
