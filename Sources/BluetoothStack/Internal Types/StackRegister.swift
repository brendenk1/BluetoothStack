import Foundation
import CoreBluetooth

struct StackRegister: Equatable, Hashable {
    let instruction: Instruction
    let addressee: Addressee?
    
    enum Instruction {
        case scanning
        case connecting
        case disconnecting
    }
    
    struct Addressee: Equatable, Hashable {
        let peripheral: CBPeripheral
        let connectionRoutes: ConnectionConfiguration.ConnectionRoutes?
        let onError: (Error) -> Void
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(peripheral)
        }
        
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
    
    static func connectingRegister(forPeripheral peripheral: CBPeripheral, connectionRoutes: ConnectionConfiguration.ConnectionRoutes, onError: @escaping (Error) -> Void) -> StackRegister {
        StackRegister(instruction: .connecting, addressee: Addressee(peripheral: peripheral, connectionRoutes: connectionRoutes, onError: onError))
    }
    
    static func disconnectingRegister(forPeripheral peripheral: CBPeripheral, onError: @escaping (Error) -> Void) -> StackRegister {
        StackRegister(instruction: .disconnecting, addressee: Addressee(peripheral: peripheral, connectionRoutes: nil, onError: onError))
    }
}
