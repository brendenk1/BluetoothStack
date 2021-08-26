import CoreBluetooth
import Foundation

final class BluetoothCentralSession: NSObject {
    typealias WhenStateChanges = (CBManagerState) -> Void
    
    init(with configuration: SessionConfiguration, onStateChange: @escaping WhenStateChanges) {
        self.onStateChange = onStateChange
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .global(qos: .background), options: configuration.options)
    }
    
    private var centralManager: CBCentralManager?
    private let onStateChange: WhenStateChanges
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
}
