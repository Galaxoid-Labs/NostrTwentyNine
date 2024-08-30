import Vapor
import Redis
import Nostr

func routes(_ app: Application) throws {
//    app.get { req async in
//        let jsonValue = try? await app.redis.send(command: "JSON.GET", with: ["nostr:5ec9baaa0dbe8cea7f33574ce18e149c381dfe1ac4d6f6820d4bbea77a91755a"].map { RESPValue(from: $0) })
//        if let data = jsonValue?.data {
//            if let event = try? JSONDecoder().decode(Event.self, from: data) {
//                print(event.id)
//                print(event.kind)
//            }
//        }
//        return "Hello, world!"
//    }

}
