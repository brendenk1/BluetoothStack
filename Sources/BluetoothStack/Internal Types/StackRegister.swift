import Foundation
import CoreBluetooth

struct StackRegister: Equatable {
    let instruction: Instruction
    let addressee: Addressee?
    
    enum Instruction {
        case scanning
        case connecting
    }
    
    struct Addressee: Equatable {
        let peripheral: CBPeripheral
        let onError: (Error) -> Void
        
        static func ==(_ lhs: Addressee, _ rhs: Addressee) -> Bool {
            lhs.peripheral.identifier == rhs.peripheral.identifier
        }
    }
    
    static func ==(_ lhs: StackRegister, _ rhs: StackRegister) -> Bool {
        lhs.instruction == rhs.instruction &&
        lhs.addressee == rhs.addressee
    }
    
    func hasPeripheralAddressee(_ peripheral: CBPeripheral) -> Bool {
        addressee?.peripheral.identifier == peripheral.identifier
    }
}

extension StackRegister {
    static var scanningRegister: StackRegister = .init(instruction: .scanning, addressee: nil)
    
    static func connectingRegister(forPeripheral peripheral: CBPeripheral, onError: @escaping (Error) -> Void) -> StackRegister {
        StackRegister(instruction: .connecting, addressee: Addressee(peripheral: peripheral, onError: onError))
    }
}
