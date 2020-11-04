//
//  TokenManager.swift
//  FRAuth
//
//  Copyright (c) 2019-2020 ForgeRock. All rights reserved.
//
//  This software may be modified and distributed under the terms
//  of the MIT license. See the LICENSE file for details.
//

import Foundation


/// TokenManager class is a management class responsible for persisting, retrieving, and refreshing OAuth2 token(s)
struct TokenManager {
    
    var oAuth2Client: OAuth2Client
    var sessionManager: SessionManager
    
    /// Initializes TokenMAnager instance with optional Access Group for shared Keychain Group identifier
    ///
    /// - Parameters:
    ///   - oAuth2Client: OAuth2Client instance for OAuth2 token protocols
    ///   - keychainManager: KeychainManager instance for secure credentials management
    public init(oAuth2Client: OAuth2Client, sessionManager: SessionManager) {
        self.oAuth2Client = oAuth2Client
        self.sessionManager = sessionManager
    }
    
    /// Persists AccessToken instance into Keychain Service
    ///
    /// - Parameter token: AccessToken instance to persist
    /// - Throws: TokenError.failToPersistToken when failed to parse AccessToken instance
    public func persist(token: AccessToken) throws {
        try self.sessionManager.setAccessToken(token: token)
    }
    
    
    /// Retrieves AccessToken object from Keychain Service
    ///
    /// - Returns: AccessToken object if it was found, and was able to decode object; otherwise nil
    /// - Throws: TokenError.failToParseToken error when retrieved data from Keychain Service failed to deserialize into AccessToken object
    func retrieveAccessTokenFromKeychain() throws -> AccessToken? {
        return try self.sessionManager.getAccessToken()
    }
    
    
    /// Retrieves AccessToken; if AccessToken expires within threshold defined in OAuth2Client, it will return a new set of OAuth2 tokens
    ///
    /// - Parameter completion: TokenCompletion block which will return an AccessToken object, or Error
    public func getAccessToken(completion: @escaping TokenCompletionCallback) {
        do {
            if let token = try self.retrieveAccessTokenFromKeychain() {
                if token.willExpireIn(threshold: self.oAuth2Client.threshold) {
                    self.refreshUsingRefreshToken(token: token) { (token, error) in
                        if let tokenError = error as? TokenError, case TokenError.nullRefreshToken = tokenError {
                            FRLog.w("No refresh_token found; exchanging SSO Token for OAuth2 tokens")
                            self.refreshUsingSSOToken(completion: completion)
                        }
                        else if let oAuthError = error as? OAuth2Error, case OAuth2Error.invalidGrant = oAuthError {
                            FRLog.w("refresh_token grant failed; try to exchange SSO Token for OAuth2 tokens")
                            self.refreshUsingSSOToken(completion: completion)
                        }
                        else {
                            FRLog.i("refresh_token grant was successful; returning new token")
                            completion(token, error)
                        }
                    }
                }
                else {
                    FRLog.v("access_token still valid; returning existing token")
                    completion(token, nil)
                }
            }
            else {
                FRLog.w("No OAuth2 token found; exchanging SSO Token for OAuth2 tokens")
                self.refreshUsingSSOToken(completion: completion)
            }
        } catch {
            FRLog.e("An error encountered while retrieving tokens from storage")
            completion(nil, error)
        }
    }
    
    
    /// Retrieves AccessToken; if AccessToken expires within threshold defined in OAuth2Client, it will return a new set of OAuth2 tokens
    ///
    /// - NOTE: This method may perform synchronous API request if the token expires within threshold. Make sure to not call this method in Main thread
    ///
    /// - Returns: AccessToken if it was able to retrieve, or get new set of OAuth2 token
    /// - Throws: AuthError will be thrown when refresh_token request failed, or TokenError
    public func getAccessToken() throws -> AccessToken? {
        if let token = try self.retrieveAccessTokenFromKeychain() {
            if token.willExpireIn(threshold: self.oAuth2Client.threshold) {
                do {
                    return try self.refreshUsingRefreshTokenAsync(token: token)
                }
                catch TokenError.nullRefreshToken {
                    FRLog.w("No refresh_token found; exchanging SSO Token for OAuth2 tokens")
                    return try self.refreshUsingSSOTokenAsync()
                }
                catch OAuth2Error.invalidGrant {
                    FRLog.w("refresh_token grant failed; try to exchange SSO Token for OAuth2 tokens")
                    return try self.refreshUsingSSOTokenAsync()
                }
            }
            else {
                FRLog.v("access_token still valid; returning existing token")
                return token
            }
        }
        else {
            FRLog.w("No OAuth2 token found; exchanging SSO Token for OAuth2 tokens")
            return try self.refreshUsingSSOTokenAsync()
        }
    }
    
    
    /// Refreshes OAuth2 token set using refresh_token
    /// - Parameter completion: TokenCompletion block which will return an AccessToken object, or Error
    func refresh(completion: @escaping TokenCompletionCallback) {
        do {
            if let token = try self.retrieveAccessTokenFromKeychain() {
                self.refreshUsingRefreshToken(token: token) { (token, error) in
                    if let tokenError = error as? TokenError, case TokenError.nullRefreshToken = tokenError {
                        FRLog.i("No refresh_token found; proceeding with SSO Token to obtain OAuth2 token(s)")
                        self.refreshUsingSSOToken(completion: completion)
                    }
                    else if let oAuthError = error as? OAuth2Error, case OAuth2Error.invalidGrant = oAuthError {
                        FRLog.i("invalid_grant received during refresh_token grant; proceeding with SSO Token to obtain OAuth2 token(s)")
                        self.refreshUsingSSOToken(completion: completion)
                    }
                    else {
                        completion(token, error)
                    }
                }
            }
            else {
                FRLog.e("No OAuth2 token(s) found")
                completion(nil, TokenError.nullToken)
            }
        }
        catch {
            completion(nil, error)
        }
    }
    
    
    /// Refreshs OAuth2 token set synchronously with current refresh_token
    /// - Throws: TokenError
    /// - Returns: renewed OAuth2 token 
    func refreshSync() throws -> AccessToken? {
        if let token = try self.retrieveAccessTokenFromKeychain() {
            do {
                return try self.refreshUsingRefreshTokenAsync(token: token)
            }
            catch TokenError.nullRefreshToken {
                FRLog.i("No refresh_token found; proceeding with SSO Token to obtain OAuth2 token(s)")
                return try self.refreshUsingSSOTokenAsync()
            }
            catch OAuth2Error.invalidGrant {
                FRLog.i("invalid_grant received during refresh_token grant; proceeding with SSO Token to obtain OAuth2 token(s)")
                return try self.refreshUsingSSOTokenAsync()
            }
        }
        else {
            FRLog.e("No OAuth2 token(s) found")
            throw TokenError.nullToken
        }
    }
    
    
    /// Revokes OAuth2 token set using either of access_token or refresh_token
    /// - Parameter completion: Completion block which will return an Error if there was any error encountered
    func revoke(completion: @escaping CompletionCallback) {
        do {
            if let token = try self.retrieveAccessTokenFromKeychain() {
                self.oAuth2Client.revoke(accessToken: token, completion: completion)
                try? self.sessionManager.setAccessToken(token: nil)
            }
            else {
                completion(TokenError.nullToken)
            }
        }
        catch {
            completion(error)
        }
    }
    
    
    /// Ends OIDC Session with given id_token
    /// - Parameters:
    ///   - idToken: id_token to be revoked, and OIDC session
    ///   - completion: Completion callback to notify the result
    func endSession(idToken: String, completion: @escaping CompletionCallback) {
        self.oAuth2Client.endSession(idToken: idToken, completion: completion)
    }
    
    
    /// Renews OAuth 2 token(s) with SSO Token
    /// - Throws: AuthApiError, TokenError
    /// - Returns: AccessToken object containing OAuth 2 token if it was successful
    func refreshUsingSSOTokenAsync() throws -> AccessToken? {
        if let ssoToken = self.sessionManager.getSSOToken() {
            do {
                let token = try self.oAuth2Client.exchangeTokenSync(token: ssoToken)
                try self.sessionManager.setAccessToken(token: token)
                return token
            }
            catch {
                if error is OAuth2Error || error is AuthApiError {
                    FRLog.i("OAuth2Error or AuthApiError received while /authorize flow with SSO Token; no more valid credentials and user authentication is required.")
                    FRLog.w("Removing all credentials and state")
                    self.clearCredentials()
                    throw AuthError.userAuthenticationRequired
                }
                else {
                    FRLog.e("Unexpected error captured during /authorize flow with SSO Token - \(error.localizedDescription)")
                    throw error
                }
            }
        }
        else {
            throw TokenError.nullToken
        }
    }
    
    
    /// Renews OAuth 2 token(s) with SSO token
    /// - Parameter completion: Completion callback to notify the result
    func refreshUsingSSOToken(completion: @escaping TokenCompletionCallback) {
        if let ssoToken = self.sessionManager.getSSOToken() {
            self.oAuth2Client.exchangeToken(token: ssoToken) { (token, error) in
                do {
                    if error is OAuth2Error || error is AuthApiError {
                        FRLog.i("OAuth2Error or AuthApiError received while /authorize flow with SSO Token; no more valid credentials and user authentication is required.")
                        FRLog.w("Removing all credentials and state")
                        self.clearCredentials()
                        completion(nil, AuthError.userAuthenticationRequired)
                    }
                    else {
                        if error == nil {
                            try self.sessionManager.setAccessToken(token: token)
                        }
                        completion(token, error)
                    }
                }
                catch {
                    FRLog.e("Unexpected error captured during /authorize flow with SSO Token - \(error.localizedDescription)")
                    completion(nil, error)
                }
            }
        }
        else {
            completion(nil, TokenError.nullToken)
        }
    }
    
    
    /// Renews OAuth 2 token(s) with refresh_token
    /// - Parameter token: AccessToken object to be consumed for renewal
    /// - Throws: AuthApiError, TokenError
    /// - Returns: AccessToken object containing OAuth 2 token if it was successful
    func refreshUsingRefreshTokenAsync(token: AccessToken) throws -> AccessToken? {
        if let refreshToken = token.refreshToken {
            let newToken = try self.oAuth2Client.refreshSync(refreshToken: refreshToken)
            newToken.sessionToken = token.sessionToken
            //  Update AccessToken's refresh_token if new AccessToken doesn't have refresh_token, and old one does.
            if newToken.refreshToken == nil, token.refreshToken != nil {
                FRLog.i("Newly granted OAuth2 token from refresh_token grant is missing refresh_token; reuse previously granted refresh_token")
                newToken.refreshToken = token.refreshToken
            }
            try self.sessionManager.setAccessToken(token: newToken)
            return token
        }
        else {
            throw TokenError.nullRefreshToken
        }
    }
    
    
    /// Renews OAuth 2 token(s) with refresh_token
    /// - Parameters:
    ///   - token: AccessToken object to be consumed for renewal
    ///   - completion: Completion callback to notify the result
    func refreshUsingRefreshToken(token: AccessToken, completion: @escaping TokenCompletionCallback) {
        if let refreshToken = token.refreshToken {
            self.oAuth2Client.refresh(refreshToken: refreshToken) { (newToken, error) in
                do {
                    newToken?.sessionToken = token.sessionToken
                    //  Update AccessToken's refresh_token if new AccessToken doesn't have refresh_token, and old one does.
                    if newToken?.refreshToken == nil, token.refreshToken != nil {
                        FRLog.i("Newly granted OAuth2 token from refresh_token grant is missing refresh_token; reuse previously granted refresh_token")
                        newToken?.refreshToken = token.refreshToken
                    }
                    try self.sessionManager.setAccessToken(token: newToken)
                    completion(newToken, error)
                }
                catch {
                    completion(nil, error)
                }
            }
        }
        else {
            completion(nil, TokenError.nullRefreshToken)
        }
    }
    
    
    /// Clears all credentials locally as there is no more valid credentials to renew user's session
    func clearCredentials() {
        self.sessionManager.keychainManager.cookieStore.deleteAll()
        try? self.sessionManager.setAccessToken(token: nil)
        self.sessionManager.setSSOToken(ssoToken: nil)
        self.sessionManager.setCurrentUser(user: nil)
        FRSession._staticSession = nil
        FRUser._staticUser = nil
        Browser.currentBrowser = nil
    }
}
