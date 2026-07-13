import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedDateProvider: DateProviding {
    private let date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public func now() -> Date { date }
}

public protocol IDProviding: Sendable {
    func next() async -> UUID
}

public struct SystemIDProvider: IDProviding {
    public init() {}
    public func next() async -> UUID { UUID() }
}

public actor FixedIDProvider: IDProviding {
    private var values: [UUID]

    public init(_ values: [UUID]) {
        self.values = values
    }

    public func next() -> UUID {
        precondition(!values.isEmpty, "FixedIDProvider exhausted")
        return values.removeFirst()
    }
}
