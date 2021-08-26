import CoreBluetooth
import Foundation

final class BluetoothCentralSession: NSObject {
    typealias WhenStateChanges = (CBManagerState) -> Void
    typealias WhenPeripheralDiscovered = (DiscoveredPeripheral) -> Void
    
    init(with configuration: SessionConfiguration, onStateChange: @escaping WhenStateChanges, onPeripheralDiscovered: @escaping WhenPeripheralDiscovered) {
        self.onStateChange = onStateChange
        self.onPeripheralDiscovered = onPeripheralDiscovered
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .global(qos: .background), options: configuration.options)
    }
    
    private var centralManager: CBCentralManager?
    private let onStateChange: WhenStateChanges
    private let onPeripheralDiscovered: WhenPeripheralDiscovered
}

extension BluetoothCentralSession {
    func startScanning(for configuration: ScanConfiguration) {
        centralManager?.scanForPeripherals(withServices: configuration.serviceIdentifiers, options: configuration.options)
    }
    
    func stopScanning() {
        centralManager?.stopScan()
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothCentralSession: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange(central.state)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let peripheral = DiscoveredPeripheral(peripheral: peripheral, advertisingData: advertisementData, rssi: RSSI)
        onPeripheralDiscovered(peripheral)
    }
}
