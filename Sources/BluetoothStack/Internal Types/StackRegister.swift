import Foundation

struct StackRegister: Equatable {
    let instruction: Instruction
    
    enum Instruction {
        case scanning
    }
}

extension StackRegister {
    static var scanningRegister: StackRegister = .init(instruction: .scanning)
}
