import Foundation
import Testing
@testable import BitcoinTicker

struct SingleInstanceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func anotherInstanceLaunchedEarlierWins() {
        let current = InstanceInfo(processIdentifier: 200, launchDate: now)
        let other = InstanceInfo(processIdentifier: 100, launchDate: now.addingTimeInterval(-5))
        #expect(SingleInstance.shouldQuit(current: current, others: [current, other]))
    }

    @Test func anotherInstanceLaunchedLaterLoses() {
        let current = InstanceInfo(processIdentifier: 200, launchDate: now)
        let other = InstanceInfo(processIdentifier: 100, launchDate: now.addingTimeInterval(5))
        #expect(!SingleInstance.shouldQuit(current: current, others: [current, other]))
    }

    @Test func equalLaunchDatesHigherProcessIdentifierQuits() {
        let low = InstanceInfo(processIdentifier: 100, launchDate: now)
        let high = InstanceInfo(processIdentifier: 200, launchDate: now)
        #expect(SingleInstance.shouldQuit(current: high, others: [low, high]))
        #expect(!SingleInstance.shouldQuit(current: low, others: [low, high]))
    }

    @Test(arguments: [(Date?.none, Date?.some(Date(timeIntervalSince1970: 0))), (Date(timeIntervalSince1970: 0), nil), (nil, nil)])
    func missingLaunchDateHigherProcessIdentifierQuits(lowDate: Date?, highDate: Date?) {
        let low = InstanceInfo(processIdentifier: 100, launchDate: lowDate)
        let high = InstanceInfo(processIdentifier: 200, launchDate: highDate)
        #expect(SingleInstance.shouldQuit(current: high, others: [low, high]))
        #expect(!SingleInstance.shouldQuit(current: low, others: [low, high]))
    }

    @Test func onlyTheCurrentProcessStays() {
        let current = InstanceInfo(processIdentifier: 200, launchDate: now)
        #expect(!SingleInstance.shouldQuit(current: current, others: [current]))
        #expect(!SingleInstance.shouldQuit(current: current, others: []))
    }
}
