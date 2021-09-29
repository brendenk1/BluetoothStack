import CoreBluetooth
import Foundation
import Synthesis

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
    
    // Logic Handlers
    /// A method that handles a connection failure with an error
    ///
    /// This *should* only be called if the error passed in is not nil, otherwise this method will cause a run time exception.
    fileprivate lazy var connectionFailureWithError: (ConnectionFailure) -> Void = { input in
        let connectionError = ConnectionError(peripheral: input.peripheral, error: input.error!)
        input.onConnectionEvent(.failure(connectionError))
    }
    
    /// A method that handles a connection failure without a reported error
    fileprivate lazy var connectionFailureNoError: (ConnectionFailure) -> Void = { input in
        let connectionError = ConnectionError.unknownError(forPeripheral: input.peripheral)
        input.onConnectionEvent(.failure(connectionError))
    }
    
    /// A method that handles a disconnect failure
    ///
    /// This *should* only be called if the error passed in is not nil, otherwise this method will cause a run time exception.
    fileprivate lazy var disconnectFailure: (DisconnectAttempt) -> Void = { input in
        let connectionError = ConnectionError(peripheral: input.peripheral, error: input.error!)
        input.onDisconnectEvent(.failure(connectionError))
    }
    
    /// A method that handled a disconnect success
    fileprivate lazy var disconnectSuccess: (DisconnectAttempt) -> Void = { input in
        input.onDisconnectEvent(.success(input.peripheral))
    }
    
    fileprivate struct ConnectionFailure {
        let onConnectionEvent: WhenConnectionEvent
        let peripheral: CBPeripheral
        let error: Error?
    }
    
    fileprivate struct DisconnectAttempt {
        let onDisconnectEvent: WhenDisconnection
        let peripheral: CBPeripheral
        let error: Error?
    }
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
        connectionFailureLogicGate
            .evaluate(ConnectionFailure(onConnectionEvent: onConnectionEvent,
                                        peripheral: peripheral,
                                        error: error))
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnectAttemptLogicGate
            .evaluate(DisconnectAttempt(onDisconnectEvent: onDisconnectEvent,
                                        peripheral: peripheral,
                                        error: error))
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

// MARK: - Connection Logic
extension BluetoothCentralSession {
    fileprivate var connectionFailureLogicGate: LogicGate<ConnectionFailure> {
        LogicGate(condition: { $0.error != nil },
                  trueCondition: connectionFailureWithError,
                  falseCondition: connectionFailureNoError)
    }
    
    fileprivate var disconnectAttemptLogicGate: LogicGate<DisconnectAttempt> {
        LogicGate(condition: { $0.error != nil },
                  trueCondition: disconnectFailure,
                  falseCondition: disconnectSuccess)
    }
}
