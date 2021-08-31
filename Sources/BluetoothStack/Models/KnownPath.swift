import CoreBluetooth
import Foundation

/// A object that encapsulates a path to interact with a remote device
public struct KnownPath: Equatable {
    /// The peripheral to interact with
    public let peripheral: CBPeripheral
    /// The service the peripheral exposes
    public let service: CBService
    /// The characteristic endpoint
    public let characteristic: CBCharacteristic
}

extension KnownPath {
    public func pathFor(_ peripheral: UUID, service: CBUUID, characteristic: CBUUID) -> Bool {
        self.peripheral.identifier == peripheral &&
        self.service.uuid == service &&
        self.characteristic.uuid == characteristic
    }
}
