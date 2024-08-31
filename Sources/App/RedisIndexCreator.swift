//
//  RedisIndexCreator.swift
//
//
//  Created by Jacob Davis on 8/30/24.
//

import Vapor
import Redis

struct RedisIndexCreator: LifecycleHandler {
    let application: Application
    func didBoot(_ application: Application) throws {
        Task {
            do {
                try await createNostrIndex()
                application.logger.info("Nostr index created successfully")
            } catch {
                application.logger.error("Failed to create Nostr index: \(error)")
            }
        }
    }
    
    func createNostrIndex() async throws {
        do {
            let _ = try await application.redis.send(command: "FT.CREATE", with: [
                RESPValue(from: "idx:nostr"),
                RESPValue(from: "ON"),
                RESPValue(from: "JSON"),
                RESPValue(from: "PREFIX"),
                RESPValue(from: "1"),
                RESPValue(from: "nostr:"),
                RESPValue(from: "SCHEMA"),
                RESPValue(from: "$.id"),
                RESPValue(from: "AS"),
                RESPValue(from: "id"),
                RESPValue(from: "TAG"),
                RESPValue(from: "$.pubkey"),
                RESPValue(from: "AS"),
                RESPValue(from: "pubkey"),
                RESPValue(from: "TAG"),
                RESPValue(from: "$.created_at"),
                RESPValue(from: "AS"),
                RESPValue(from: "created_at"),
                RESPValue(from: "NUMERIC"),
                RESPValue(from: "$.kind"),
                RESPValue(from: "AS"),
                RESPValue(from: "kind"),
                RESPValue(from: "NUMERIC"),
                RESPValue(from: "$.tags[*][*]"),
                RESPValue(from: "AS"),
                RESPValue(from: "tags"),
                RESPValue(from: "TAG"),
                RESPValue(from: "$.content"),
                RESPValue(from: "AS"),
                RESPValue(from: "content"),
                RESPValue(from: "TEXT")
            ]).get()
            
            application.logger.notice("idx:nostr Index created")
        } catch {
            if let redisError = error as? RedisError,
               redisError.message.contains("Index already exists") {
            } else {
                throw error
            }
        }
    }
}
