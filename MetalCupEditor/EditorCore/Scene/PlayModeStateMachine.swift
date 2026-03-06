import Foundation

final class PlayModeStateMachine {
    enum State: String {
        case edit
        case play
        case simulate
        case pausedPlay
        case pausedSimulate
    }

    enum Event: String {
        case play
        case stop
        case simulate
        case resetSimulate
        case pause
        case resume
    }

    private(set) var state: State = .edit
    private let onIllegalTransition: ((String) -> Void)?

    init(onIllegalTransition: ((String) -> Void)? = nil) {
        self.onIllegalTransition = onIllegalTransition
    }

    var isPlaying: Bool {
        state == .play || state == .pausedPlay
    }

    var isPaused: Bool {
        state == .pausedPlay || state == .pausedSimulate
    }

    var isSimulating: Bool {
        state == .simulate || state == .pausedSimulate
    }

    @discardableResult
    func send(_ event: Event) -> Bool {
        guard let next = nextState(for: event) else {
            reportIllegalTransition(event: event, state: state)
            return false
        }
        state = next
        return true
    }

    func forceSetState(_ next: State) {
        state = next
    }

    private func nextState(for event: Event) -> State? {
        switch (state, event) {
        case (.edit, .play):
            return .play
        case (.edit, .simulate):
            return .simulate
        case (.play, .stop), (.pausedPlay, .stop), (.simulate, .stop), (.pausedSimulate, .stop):
            return .edit
        case (.simulate, .resetSimulate), (.pausedSimulate, .resetSimulate):
            return .edit
        case (.play, .pause):
            return .pausedPlay
        case (.simulate, .pause):
            return .pausedSimulate
        case (.pausedPlay, .resume):
            return .play
        case (.pausedSimulate, .resume):
            return .simulate
        default:
            return nil
        }
    }

    private func reportIllegalTransition(event: Event, state: State) {
        let message = "PlayModeStateMachine illegal transition: state=\(state.rawValue) event=\(event.rawValue)"
        onIllegalTransition?(message)
    }
}
