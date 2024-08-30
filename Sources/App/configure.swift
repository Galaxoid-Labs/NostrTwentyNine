import Vapor
import Redis
import Nostr

public func configure(_ app: Application) async throws {
    
    app.redis.configuration = try RedisConfiguration(hostname: "localhost", port: 6379)
    
    try routes(app)
    
    let nostrConfig = NostrConfig(allowedKinds: [.setMetadata, .groupChatMessage])
    
    try app.register(collection: EventController(config: nostrConfig, redis: app.redis))
}
