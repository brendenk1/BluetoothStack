import Foundation

enum StackError: Error {
    case invalidInstruction
    case systemNotReady
    case unknownDevice
    case unknownPath
}
