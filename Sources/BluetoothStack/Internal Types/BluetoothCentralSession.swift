import CoreBluetooth
import Foundation

final class BluetoothCentralSession: NSObject {
    typealias ConnectionEvent = Result<CBPeripheral, ConnectionError>
    typealias DisconnectionEvent = Result<CBPeripheral, ConnectionError>
    typealias WhenStateChanges = (CBManagerState) -> Void
    typealias WhenPeripheralDiscovered = (DiscoveredPeripheral) -> Void
    typealias WhenConnectionEvent = (ConnectionEvent) -> Void
    typealias WhenDisconnection = (DisconnectionEvent) -> Void
    
    init(with configuration: SessionConfiguration,
         onStateChange: @escaping WhenStateChanges,
         onPeripheralDiscovered: @escaping WhenPeripheralDiscovered,
         onConnectionEvent: @escaping WhenConnectionEvent,
         onDisconnectEvent: @escaping WhenDisconnection) {
        self.onStateChange = onStateChange
        self.onPeripheralDiscovered = onPeripheralDiscovered
        self.onConnectionEvent = onConnectionEvent
        self.onDisconnectEvent = onDisconnectEvent
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated), options: configuration.options)
    }
    
    private var centralManager: CBCentralManager?
    private let onStateChange: WhenStateChanges
    private let onPeripheralDiscovered: WhenPeripheralDiscovered
    private let onConnectionEvent: WhenConnectionEvent
    private let onDisconnectEvent: WhenDisconnection
}

extension BluetoothCentralSession {
    func startScanning(for configuration: ScanConfiguration) {
        centralManager?.scanForPeripherals(withServices: configuration.serviceIdentifiers, options: configuration.options)
    }
    
    func stopScanning() {
        centralManager?.stopScan()
    }
    
    func connectToPeripheral(connectionConfiguration configuration: ConnectionConfiguration) {
        centralManager?.connect(configuration.peripheral, options: configuration.options)
    }
    
    func cancelConnection(toPeripheral peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
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

extension BluetoothCentralSession {
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnectionEvent(.success(peripheral))
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            let connectionError = ConnectionError(peripheral: peripheral, error: error)
            onConnectionEvent(.failure(connectionError))
        } else {
            let connectionError = ConnectionError.unknownError(forPeripheral: peripheral)
            onConnectionEvent(.failure(connectionError))
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            let connectionError = ConnectionError(peripheral: peripheral, error: error)
            onDisconnectEvent(.failure(connectionError))
        } else {
            onDisconnectEvent(.success(peripheral))
        }
    }
    
    func knownPeripheral(withIdentifier identifier: UUID) -> CBPeripheral? {
        centralManager?
            .retrievePeripherals(withIdentifiers: [identifier])
            .first(where: { $0.identifier == identifier })
    }
    
    func connectedPeripheral(withServices identifiers: [CBUUID]) -> CBPeripheral? {
        centralManager?
            .retrieveConnectedPeripherals(withServices: identifiers)
            .first(where: { peripheral in
                let services = Set(peripheral.services ?? [])
                let serviceIdentifiers = Set(services.map { $0.uuid })
                return serviceIdentifiers.isSuperset(of: identifiers)
            })
    }
}

extension BluetoothCentralSession {
    struct ConnectionError: Error {
        let peripheral: CBPeripheral
        let error: Error
        
        enum GeneralError: Error {
            case unknownError
        }
        
        static func unknownError(forPeripheral peripheral: CBPeripheral) -> ConnectionError {
            ConnectionError(peripheral: peripheral, error: GeneralError.unknownError)
        }
    }
}
