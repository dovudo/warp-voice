import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
var key = HoldKey()
check(key.down(modified: false) == .wait, "plain down waits")
check(key.up() == .typeKey, "short press types the key")
check(key.down(modified: false) == .wait, "second down waits")
check(key.threshold() == .startRecording, "hold starts recording")
check(key.up() == .stopRecording, "release stops recording")
check(key.down(modified: true) == .pass, "modified key passes through")
check(key.down(modified: false) == .wait, "third down waits")
check(key.otherKey() == .typeKey, "chord flushes pending key")
check(key.up() == .pass, "flushed key release passes through")
print("Hold-key behavior passed")
check(shouldPaste(sameApp: true, initialFocusKnown: false, sameFocus: false), "unavailable accessibility focus allows paste in same app")
check(!shouldPaste(sameApp: false, initialFocusKnown: false, sameFocus: false), "changed app prevents paste")
check(!shouldPaste(sameApp: true, initialFocusKnown: true, sameFocus: false), "changed known field prevents paste")
check(shouldPaste(sameApp: true, initialFocusKnown: true, sameFocus: true), "unchanged field allows paste")
