import Foundation

func shouldPaste(sameApp: Bool, initialFocusKnown: Bool, sameFocus: Bool) -> Bool {
    sameApp && (!initialFocusKnown || sameFocus)
}

enum KeyAction: Equatable { case pass, wait, typeKey, startRecording, stopRecording }
struct HoldKey {
    private enum State { case idle, pending, recording, forwarded }
    private var state = State.idle
    mutating func down(modified: Bool) -> KeyAction {
        guard state == .idle else { return .wait }
        guard !modified else { return .pass }
        state = .pending
        return .wait
    }
    mutating func threshold() -> KeyAction {
        guard state == .pending else { return .pass }
        state = .recording
        return .startRecording
    }
    mutating func up() -> KeyAction {
        switch state {
        case .pending: state = .idle; return .typeKey
        case .recording: state = .idle; return .stopRecording
        case .forwarded: state = .idle; return .pass
        case .idle: return .pass
        }
    }
    mutating func otherKey() -> KeyAction {
        guard state == .pending else { return .pass }
        state = .forwarded
        return .typeKey
    }
}
