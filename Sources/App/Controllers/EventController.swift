//
//  EventController.swift
//
//
//  Created by Jacob Davis on 8/29/24.
//

import Foundation
import Vapor
import Redis
import Nostr

class EventController: RouteCollection, @unchecked Sendable {
    
    let config: NostrConfig
    let subscriptionManager: SubscriptionManager
    
    init(config: NostrConfig, redis: RedisClient) {
        self.config = config
        self.subscriptionManager = SubscriptionManager(redis: redis)
    }
    
    func boot(routes: RoutesBuilder) throws {
        routes.webSocket("", onUpgrade: handleWebSocket)
    }
    
    @Sendable
    func handleWebSocket(req: Request, ws: WebSocket) {
        let clientId = req.id
        
        ws.onText { [weak self] ws, text in
            guard let self = self else { return }
            do {
                let message = try JSONDecoder().decode(ClientMessage.self, from: Data(text.utf8))
                switch message {
                case .subscribe(let subscription):
                    self.subscriptionManager.addSubscription(clientId: clientId, subscription: subscription, ws: ws)
                case .unsubscribe(let subscriptionId):
                    self.subscriptionManager.removeSubscription(clientId: clientId, subscriptionId: subscriptionId, ws: ws)
                case .event(let event):
                        // TODO: Check if event valid
                        // Check if event created_at within time range
                        await self.subscriptionManager.processNewEvent(clientId: clientId, ws: ws, event: event)
                }
            } catch {
                print("Error processing message: \(error)")
            }
        }
        
        ws.onClose.whenComplete { [weak self] _ in
            // Clean up subscriptions when the connection closes
            self?.subscriptionManager.removeSubscription(clientId: clientId, subscriptionId: "all", ws: ws)
        }
    }
}

class SubscriptionManager: @unchecked Sendable {
    
    private var subscriptions: [String: SubscriptionHandle] = [:]
    private let redis: RedisClient
    private let eventQueue: DispatchQueue

    init(redis: RedisClient) {
        self.redis = redis
        self.eventQueue = DispatchQueue(label: "nostr.twenty.nine.queue", attributes: .concurrent)
    }

    func addSubscription(clientId: String, subscription: Subscription, ws: WebSocket) {
        eventQueue.async(flags: .barrier) { [weak self] in
            if self?.subscriptions[clientId] == nil {
                self?.subscriptions[clientId] = SubscriptionHandle(subscriptions: [subscription], websocket: ws)
            } else if let idx = self?.subscriptions[clientId]?.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                self?.subscriptions[clientId]?.subscriptions[idx] = subscription
            } else {
                self?.subscriptions[clientId]?.subscriptions.append(subscription)
            }
        }
        
        // Process existing events
        // TODO: Do we send the subs again if the same id was used???
        Task {
            await self.sendExistingEvents(clientId: clientId, subscription: subscription, ws: ws)
        }
    }

    func removeSubscription(clientId: String, subscriptionId: String, ws: WebSocket) {
        eventQueue.async(flags: .barrier) {
            self.subscriptions[clientId]?.subscriptions.removeAll { $0.id == subscriptionId }
        }
    }

    func processNewEvent(clientId: String, ws: WebSocket, event: Event) async {
        
        if let eventId = event.id, let jsonEvent = event.string() {
            // TODO: Check kind to determine if this is replaceable event.
            // If not, we will set the flag to no-op if event is already in db
            // We can set RESPValue(from: "NX") as last argument to do this.
            
            var respValues: [RESPValue] = [
                RESPValue(from: "nostr:\(eventId)"),
                RESPValue(from: "$"),
                RESPValue(from: jsonEvent),
                RESPValue(from: "NX")
            ]
            
            if event.kind == .setMetadata || event.kind == .groupMetadata {
                respValues.removeLast()
            }
            
            do {
                let result = try await redis.send(command: "JSON.SET", with: respValues).get()
                print(result)

                if let relayMessage = try? RelayMessage.ok(eventId, true, "").string() {
                    try? await ws.send(relayMessage)
                }
                
                eventQueue.async { // TODO: FIX ME
        //            for (clientId, clientSubscriptions) in self.subscriptions {
        //                for subscription in clientSubscriptions {
        //                    if self.eventMatchesFilters(event: event, filters: subscription.filters) {
        //                        Task {
        //                            await self.sendEventToClient(clientId: clientId, subscriptionId: subscription.id, event: event)
        //                        }
        //                    }
        //                }
        //            }
                }
                
            } catch {
                if let relayMessage = try? RelayMessage.ok(eventId, false, "error: \(error.localizedDescription)").string() {
                    try? await ws.send(relayMessage)
                }
            }
        }
    }
    
    private func sendExistingEvents(clientId: String, subscription: Subscription, ws: WebSocket) async {
        // Query Redis for matching events
        // This is a placeholder - you'll need to implement the actual query logic
        let events = await queryRedisForEvents(filters: subscription.filters)
        
        // Send events to the client
        for event in events {
            await sendEventToClient(clientId: clientId, subscriptionId: subscription.id, event: event)
        }
    }

    private func eventMatchesFilters(event: Event, filters: [Filter]) -> Bool {
        // Implement filter matching logic
        // Return true if the event matches any of the filters
        return true // Placeholder
    }

    private func sendEventToClient(clientId: String, subscriptionId: String, event: Event) async {
        // Implement logic to send the event to the client
        // This might involve using WebSockets or another real-time communication method
    }

    private func queryRedisForEvents(filters: [Filter]) async -> [Event] {
        // Implement Redis query logic based on filters
        // Return matching events
        return [] // Placeholder
    }
}

struct SubscriptionHandle {
    var subscriptions: [Subscription]
    let websocket: WebSocket
}

struct NostrConfig {
    let allowedKinds: [Kind]
    
    init(allowedKinds: [Kind]) {
        self.allowedKinds = allowedKinds
    }
    
    func isKindAllowed(_ kind: Kind) -> Bool {
        return allowedKinds.contains(kind)
    }
    
    func isKindsAllowed(_ kinds: [Kind]) -> Bool {
        return kinds.allSatisfy { allowedKinds.contains($0) }
    }
}

extension Event: Content {}
