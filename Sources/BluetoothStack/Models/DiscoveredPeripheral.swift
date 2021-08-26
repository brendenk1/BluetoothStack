import CoreBluetooth
import Foundation

/*
 A object that encapsulates advertisement data when the system discovers a peripheral
 */
public struct DiscoveredPeripheral: Equatable, Hashable, Comparable {
    internal init(peripheral: CBPeripheral, advertisingData: [String : Any], rssi: NSNumber) {
        self.peripheral = peripheral
        self.advertisingData = advertisingData
        self.rssi = rssi
        self.discoveryDate = Date()
    }
    
    public let peripheral: CBPeripheral
    public let advertisingData: [String: Any]
    public let rssi: NSNumber
    public let discoveryDate: Date
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(peripheral)
    }
    
    public static func ==(_ lhs: DiscoveredPeripheral, _ rhs: DiscoveredPeripheral) -> Bool {
        lhs.peripheral == rhs.peripheral
    }
    
    public static func <(_ lhs: DiscoveredPeripheral, _ rhs: DiscoveredPeripheral) -> Bool {
        lhs.rssi.decimalValue < rhs.rssi.decimalValue
    }
    
    public static func <=(_ lhs: DiscoveredPeripheral, _ rhs: DiscoveredPeripheral) -> Bool {
        lhs.rssi.decimalValue <= rhs.rssi.decimalValue
    }
    
    public static func >(_ lhs: DiscoveredPeripheral, _ rhs: DiscoveredPeripheral) -> Bool {
        lhs.rssi.decimalValue > rhs.rssi.decimalValue
    }
    
    public static func >=(_ lhs: DiscoveredPeripheral, _ rhs: DiscoveredPeripheral) -> Bool {
        lhs.rssi.decimalValue >= rhs.rssi.decimalValue
    }
}

extension DiscoveredPeripheral: Identifiable {
    public var id: UUID {
        peripheral.identifier
    }
}

extension Array: Identifiable {
    public var id: Int {
        self.count
    }
}
