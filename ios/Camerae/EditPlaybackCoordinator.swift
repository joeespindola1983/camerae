import AVFoundation
import Foundation

struct EditPlaybackItem: Equatable, Sendable {
    let id: UUID
    let url: URL
}

enum EditPlaybackState: Equatable {
    case idle
    case preparing
    case ready(currentItemID: UUID?)
    case playing(currentItemID: UUID)
    case paused(currentItemID: UUID?)
    case finished
    case failed(message: String)
}

@MainActor
protocol EditPlaybackQueueing: AnyObject {
    var onCurrentItemChanged: ((UUID?) -> Void)? { get set }
    func replace(with items: [EditPlaybackItem])
    func play()
    func pause()
    func restart()
    func removeAll()
}

@MainActor
final class EditPlaybackCoordinator: ObservableObject {
    @Published private(set) var state: EditPlaybackState = .idle

    private let engine: any EditPlaybackQueueing
    private(set) var items: [EditPlaybackItem] = []
    private var currentItemID: UUID?
    private var wantsPlayback = false

    var player: AVQueuePlayer? {
        (engine as? AVQueuePlaybackEngine)?.player
    }

    var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    var highlightedItemID: UUID? {
        switch state {
        case .ready(let id), .paused(let id): return id
        case .playing(let id): return id
        default: return nil
        }
    }

    convenience init() {
        self.init(engine: AVQueuePlaybackEngine())
    }

    init(engine: any EditPlaybackQueueing) {
        self.engine = engine
        engine.onCurrentItemChanged = { [weak self] id in
            self?.currentItemChanged(id)
        }
    }

    func prepare(items: [EditPlaybackItem]) {
        wantsPlayback = false
        self.items = items
        currentItemID = items.first?.id
        guard !items.isEmpty else {
            engine.removeAll()
            state = .idle
            return
        }
        state = .preparing
        engine.replace(with: items)
        state = .ready(currentItemID: currentItemID)
    }

    func play() {
        guard let id = currentItemID ?? items.first?.id else { return }
        if state == .finished {
            restart()
            return
        }
        wantsPlayback = true
        engine.play()
        state = .playing(currentItemID: id)
    }

    func pause() {
        wantsPlayback = false
        engine.pause()
        state = .paused(currentItemID: currentItemID)
    }

    func restart() {
        guard let first = items.first else { return }
        wantsPlayback = true
        currentItemID = first.id
        engine.restart()
        engine.play()
        state = .playing(currentItemID: first.id)
    }

    func tearDown() {
        wantsPlayback = false
        items = []
        currentItemID = nil
        engine.removeAll()
        state = .idle
    }

    private func currentItemChanged(_ id: UUID?) {
        guard let id else {
            wantsPlayback = false
            currentItemID = nil
            state = items.isEmpty ? .idle : .finished
            return
        }
        currentItemID = id
        if wantsPlayback {
            state = .playing(currentItemID: id)
        } else if case .ready = state {
            state = .ready(currentItemID: id)
        } else {
            state = .paused(currentItemID: id)
        }
    }
}

@MainActor
private final class AVQueuePlaybackEngine: EditPlaybackQueueing {
    let player = AVQueuePlayer()
    var onCurrentItemChanged: ((UUID?) -> Void)?

    private var sourceItems: [EditPlaybackItem] = []
    private var itemIDs: [ObjectIdentifier: UUID] = [:]
    private var currentObservation: NSKeyValueObservation?
    private var finishObserver: NSObjectProtocol?

    init() {
        currentObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            guard let item = change.newValue ?? nil else { return }
            Task { @MainActor [weak self] in
                guard let self, let id = itemIDs[ObjectIdentifier(item)] else { return }
                onCurrentItemChanged?(id)
            }
        }
    }

    deinit {
        if let finishObserver {
            NotificationCenter.default.removeObserver(finishObserver)
        }
    }

    func replace(with items: [EditPlaybackItem]) {
        sourceItems = items
        rebuildQueue()
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func restart() {
        rebuildQueue()
        onCurrentItemChanged?(sourceItems.first?.id)
    }

    func removeAll() {
        player.pause()
        player.removeAllItems()
        sourceItems = []
        itemIDs = [:]
        removeFinishObserver()
    }

    private func rebuildQueue() {
        player.pause()
        player.removeAllItems()
        itemIDs = [:]
        removeFinishObserver()

        var lastPlayerItem: AVPlayerItem?
        for item in sourceItems {
            let playerItem = AVPlayerItem(url: item.url)
            itemIDs[ObjectIdentifier(playerItem)] = item.id
            player.insert(playerItem, after: nil)
            lastPlayerItem = playerItem
        }
        if let lastPlayerItem {
            finishObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: lastPlayerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onCurrentItemChanged?(nil)
                }
            }
        }
    }

    private func removeFinishObserver() {
        if let finishObserver {
            NotificationCenter.default.removeObserver(finishObserver)
            self.finishObserver = nil
        }
    }
}
