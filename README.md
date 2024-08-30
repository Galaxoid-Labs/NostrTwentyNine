# NostrTwentyNine - Nip29 focused relay written in Swift/Vapor

### Here be dragons 🚨🚨🚨
This repo is a work in progress and not ready for use and likely will not work. I would not even try it at the moment. I setup the repo simply to keep track of my work and for transparency such that my work can verified and followed.

Currently configs and database connection hard-coded so you'd have to play around with these if your setup is not the same as what I have.

#### Linux

- Install [Redis-Stack](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/linux/)
- Run Redis-Stack
- Install [Swiftly](https://swiftlang.github.io/swiftly/)
    -  Install swift `swiftly install latest`
- Clone the repo and cd into NostrTwentyNine
- run `swift run App`

### MacOS

- Install [Redis-Stack](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/mac-os/)
- Clone the repo and cd into NostrTwentyNine
- run `swift run App`

### Docker

I havent currently gotten docker to work yet, but the goal is to make it work so its easy to run everything with a single command
