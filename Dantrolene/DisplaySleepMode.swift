import Foundation

enum DisplaySleepMode: Hashable {
    case matchSystem
    case custom(minutes: Int)

    var tag: Int {
        switch self {
        case .matchSystem: 0
        case let .custom(m): m
        }
    }

    init(tag: Int) {
        self = tag == 0 ? .matchSystem : .custom(minutes: tag)
    }
}
