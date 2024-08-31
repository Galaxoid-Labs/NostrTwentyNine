import Vapor
import Redis
import Nostr

public func configure(_ app: Application) async throws {
   
    let redisURL = Environment.get("REDIS_HOSTNAME") ?? "127.0.0.1"
    let redisPORT = Environment.get("REDIS_PORT").flatMap(Int.init) ?? 6379
    app.redis.configuration = try RedisConfiguration(hostname: redisURL, port: redisPORT)
    
    try routes(app)
    
    let nostrConfig = NostrConfig(allowedKinds: [.setMetadata, .groupChatMessage])
    try app.register(collection: EventController(config: nostrConfig, redis: app.redis))
    
    app.lifecycle.use(RedisIndexCreator(application: app))
    
}
