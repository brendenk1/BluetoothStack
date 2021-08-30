import Combine
import CoreBluetooth
import Foundation
import Synthesis

/// An object responsible for managing the `Bluetooth` stack
///
/// Currently the stack is only designed for `Central` management and does not support background modes.
public final class BluetoothStack: ObservableObject {
    public init() {
        configureFormattingForManagers()
    }
    
    public typealias WhenError = (Error) -> Void
    public typealias SystemReady = Bool
    public typealias SystemReadyTroubleshooting = (systemState: CBManagerState?, authorizationState: CBManagerAuthorization)
    public typealias SystemScanning = Bool
    public typealias AvailablePeripherals = Array<DiscoveredPeripheral>
    public typealias ConnectedPeripherals = Array<CBPeripheral>
    
    fileprivate typealias DiscoveredPeripherals = Set<DiscoveredPeripheral>
    fileprivate typealias ConnectedSystemPeripherals = Set<CBPeripheral>
    fileprivate typealias Registry = Array<StackRegister>
    
    private var centralSession: BluetoothCentralSession?
    
    // Kernels
    private let systemState: Kernel<CBManagerState> = Kernel()
    private let systemRegister: Kernel<Registry> = Kernel()
    private let systemDiscoveredPeripherals: Kernel<DiscoveredPeripherals> = Kernel()
    private let systemConnectingPeripherals: Kernel<ConnectedSystemPeripherals> = Kernel()
    private let systemConnectedPeripherals: Kernel<ConnectedSystemPeripherals> = Kernel()
    
    // Managers
    private let systemReady: Manager<SystemReady> = Manager()
    private let systemScanning: Manager<SystemScanning> = Manager()
    private let systemPeripherals: Manager<AvailablePeripherals> = Manager()
    private let connectingPeripherals: Manager<ConnectedPeripherals> = Manager()
    private let connectedPeripherals: Manager<ConnectedPeripherals> = Manager()
    
    // Actions
    fileprivate func onStateChange(_ state: CBManagerState) {
        Action(connector: SetValueConnection(value: state),
               kernel: systemState)
            .execute()
    }
    
    fileprivate func onPeripheralDiscovery(_ discoveredPeripheral: DiscoveredPeripheral) {
        var discoveredPeripherals = systemDiscoveredPeripherals.currentValue ?? Set()
        discoveredPeripherals.update(with: discoveredPeripheral)
        Action(connector: SetValueConnection(value: discoveredPeripherals),
               kernel: systemDiscoveredPeripherals)
            .execute()
    }
    
    fileprivate func onConnectionEvent(_ connectionEvent: BluetoothCentralSession.ConnectionEvent) {
        switch connectionEvent {
        case .success(let peripheral):
            if let registryItem = findAddresseeInRegistry(peripheral, forInstruction: .connecting) {
                removeInRegistry(registryItem)
            }
            removeConnectingPeripheral(peripheral)
            addConnectedPeripheral(peripheral)
        case .failure(let connectionError):
            if let registryItem = findAddresseeInRegistry(connectionError.peripheral, forInstruction: .connecting) {
                removeInRegistry(registryItem)
                registryItem.addressee?.onError(connectionError)
            }
        }
    }
    
    fileprivate func onDisconnectionEvent(_ disconnectionEvent: BluetoothCentralSession.DisconnectionEvent) {
        switch disconnectionEvent {
        case .success(let peripheral):
            if let connectionRegistryItem = findAddresseeInRegistry(peripheral, forInstruction: .connecting) {
                removeInRegistry(connectionRegistryItem)
            }
            if let disconnectRegistryItem = findAddresseeInRegistry(peripheral, forInstruction: .disconnecting) {
                removeInRegistry(disconnectRegistryItem)
            }
        case .failure(let disconnectionError):
            if let connectionRegistryItem = findAddresseeInRegistry(disconnectionError.peripheral, forInstruction: .connecting) {
                removeInRegistry(connectionRegistryItem)
                connectionRegistryItem.addressee?.onError(disconnectionError)
            }
            if let disconnectRegistryItem = findAddresseeInRegistry(disconnectionError.peripheral, forInstruction: .disconnecting) {
                removeInRegistry(disconnectRegistryItem)
                disconnectRegistryItem.addressee?.onError(disconnectionError)
            }
        }
    }
    
    // Formatted Values
    private func configureFormattingForManagers() {
        BluetoothStack.formatForSystemReady(basedOn: systemState, toManager: systemReady)
        BluetoothStack.formatForSystemScanning(basedOn: systemRegister, toManager: systemScanning)
        BluetoothStack.formatForDiscoveredPeripherals(basedOn: systemDiscoveredPeripherals, toManager: systemPeripherals)
        BluetoothStack.formatForConnectingPeripherals(basedOn: systemConnectingPeripherals, toManager: connectingPeripherals)
        BluetoothStack.formatForConnectedPeripherals(basedOn: systemConnectedPeripherals, toManager: connectedPeripherals)
    }
    
    // Helpers
    
    // MARK: System
    fileprivate func verifySystemState() throws {
        if (systemState.currentValue == .poweredOn) == false {
            throw StackError.systemNotReady
        }
    }
    
    // MARK: Registry
    fileprivate func checkRegistry(doesNotContainInstruction instruction: StackRegister.Instruction) throws {
        if systemRegister.currentValue?.contains(where: { $0.instruction == instruction }) == true {
            throw StackError.invalidInstruction
        }
    }
    
    fileprivate func checkRegistry(doesNotContainInstruction instruction: StackRegister.Instruction, forAddressee addressee: CBPeripheral) throws {
        guard findAddresseeInRegistry(addressee, forInstruction: instruction) == nil
        else { throw StackError.invalidInstruction }
    }
    
    fileprivate func checkRegistry(containsInstruction instruction: StackRegister.Instruction) throws {
        if systemRegister.currentValue?.contains(where: { $0.instruction == instruction }) == false {
            throw StackError.invalidInstruction
        }
    }
    
    fileprivate func insertInRegistry(_ item: StackRegister) {
        var registry = systemRegister.currentValue ?? []
        registry.append(item)
        Action(connector: SetValueConnection(value: registry),
               kernel: systemRegister)
            .execute()
    }
    
    fileprivate func removeInRegistry(_ item: StackRegister) {
        var registry = systemRegister.currentValue
        if let index = registry?.firstIndex(where: { $0 == item }) {
            registry?.remove(at: index)
        }
        Action(connector: SetValueConnection(value: registry),
               kernel: systemRegister)
            .execute()
    }
    
    fileprivate func findAddresseeInRegistry(_ peripheral: CBPeripheral, forInstruction instruction: StackRegister.Instruction) -> StackRegister? {
        systemRegister
            .currentValue?
            .compactMap { $0 }
            .filter { $0.hasPeripheralAddressee(peripheral) }
            .compactMap { $0 }
            .filter { $0.instruction == instruction }
            .compactMap { $0 }
            .last
    }
    
    // MARK: Connecting Peripherals
    fileprivate func addConnectingPeripheral(_ peripheral: CBPeripheral) {
        var connectingPeripherals = systemConnectingPeripherals.currentValue ?? []
        connectingPeripherals.update(with: peripheral)
        Action(connector: SetValueConnection(value: connectingPeripherals),
               kernel: systemConnectingPeripherals)
            .execute()
    }
    
    fileprivate func removeConnectingPeripheral(_ peripheral: CBPeripheral) {
        var connectingPeripherals = systemConnectingPeripherals.currentValue ?? []
        connectingPeripherals.remove(peripheral)
        Action(connector: SetValueConnection(value: connectingPeripherals),
               kernel: systemConnectingPeripherals)
            .execute()
    }
    
    fileprivate func peripheralIsInConnecting(_ peripheral: CBPeripheral) -> Bool {
        systemConnectingPeripherals
            .currentValue?
            .contains(peripheral) == true
    }
    
    fileprivate func findPeripheralToReconnect(_ identifier: UUID, services: [CBUUID]) throws -> CBPeripheral {
        if let knownPeripheral = centralSession?.knownPeripheral(withIdentifier: identifier) {
            return knownPeripheral
        } else if let systemConnectedPeripheral = centralSession?.connectedPeripheral(withServices: services) {
            return systemConnectedPeripheral
        }
        throw StackError.unknownDevice
    }
    
    // MARK: Connected Peripherals
    fileprivate func addConnectedPeripheral(_ peripheral: CBPeripheral) {
        var connectedPeripherals = systemConnectedPeripherals.currentValue ?? []
        connectedPeripherals.update(with: peripheral)
        Action(connector: SetValueConnection(value: connectedPeripherals),
               kernel: systemConnectedPeripherals)
            .execute()
    }
    
    fileprivate func removeConnectedPeripheral(_ peripheral: CBPeripheral) {
        var connectedPeripherals = systemConnectedPeripherals.currentValue ?? []
        connectedPeripherals.remove(peripheral)
        Action(connector: SetValueConnection(value: connectedPeripherals),
               kernel: systemConnectedPeripherals)
            .execute()
    }
    
    fileprivate func peripheralIsInConnected(_ peripheral: CBPeripheral) -> Bool {
        systemConnectedPeripherals
            .currentValue?
            .contains(peripheral) == true
    }
}

// MARK: - Public Interface
extension Bool: Identifiable {
    public var id: Bool {
        self
    }
}

extension BluetoothStack {
    // MARK: System Ready State
    
    /// A publisher that will emit `SystemReady` values
    ///
    /// This publisher is guaranteed to emit on the `Main` thread
    public var systemReadyPublisher: AnyPublisher<SystemReady?, Never> {
        systemReady
            .$value
            .eraseToAnyPublisher()
    }
    
    /// A method that is used to initialize a `Bluetooth` session
    public func initializeSession(with configuration: SessionConfiguration) {
        centralSession = BluetoothCentralSession(with: configuration,
                                                 onStateChange: { [weak self] state in self?.onStateChange(state) },
                                                 onPeripheralDiscovered: { [weak self] discoveredPeripheral in self?.onPeripheralDiscovery(discoveredPeripheral) },
                                                 onConnectionEvent: { [weak self] connectionEvent in self?.onConnectionEvent(connectionEvent) },
                                                 onDisconnectEvent: { [weak self] disconnectEvent in self?.onDisconnectionEvent(disconnectEvent) })
    }
    
    /// A function to troubleshoot if a system is not `ready`
    ///
    /// The `CBManagerState` will be reported as `nil` until the session is initialized
    public func troubleshootSystemReady() -> SystemReadyTroubleshooting {
        (systemState.currentValue, CBManager.authorization)
    }
    
    // MARK: System Scanning
    
    /// A publisher that will emit `SystemScanning` values
    ///
    /// This publisher is guaranteed to emit on the `Main` thread
    public var systemScanningPublisher: AnyPublisher<SystemScanning, Never> {
        systemScanning
            .$value
            .replaceNil(with: false)
            .eraseToAnyPublisher()
    }
    
    /// A method to start scanning for peripherals
    public func startScanning(for configuration: ScanConfiguration, onError: @escaping WhenError) {
        do {
            try verifySystemState()
            try checkRegistry(doesNotContainInstruction: .scanning)
            insertInRegistry(.scanningRegister)
            centralSession?.startScanning(for: configuration)
        } catch {
            onError(error)
        }
    }
    
    /// A method to stop scanning for peripherals
    public func stopScanning(onError: @escaping WhenError) {
        do {
            try checkRegistry(containsInstruction: .scanning)
            centralSession?.stopScanning()
            removeInRegistry(.scanningRegister)
        } catch {
            onError(error)
        }
    }
    
    // MARK: Available Peripherals
    
    /// A publisher that will emit `AvailablePeripherals` values sorted by RSSI values 
    ///
    /// This publisher is guaranteed to emit on the `Main` thread
    public var availablePeripheralPublisher: AnyPublisher<AvailablePeripherals, Never> {
        systemPeripherals
            .$value
            .replaceNil(with: [])
            .eraseToAnyPublisher()
    }
    
    // MARK: Connected Peripherals
    /// A publisher that will emit `ConnectedPeripherals` values representing peripherals pending connection with the system
    ///
    /// This publisher is guaranteed to emit on the `Main` thread
    public var connectingPeripheralsPublisher: AnyPublisher<ConnectedPeripherals, Never> {
        connectingPeripherals
            .$value
            .replaceNil(with: [])
            .eraseToAnyPublisher()
    }
    
    /// A publisher that will emit `ConnectedPeripherals` values
    ///
    /// This publisher is guaranteed to emit on the `Main` thread
    public var connectedPeripheralPublisher: AnyPublisher<ConnectedPeripherals, Never> {
        connectedPeripherals
            .$value
            .replaceNil(with: [])
            .eraseToAnyPublisher()
    }
    
    /// A method that allows for the connection of a peripheral given a configuration
    public func connectPeripheral(withConfiguration configuration: ConnectionConfiguration, onError: @escaping (Error) -> Void) {
        do {
            try verifySystemState()
            try checkRegistry(doesNotContainInstruction: .connecting, forAddressee: configuration.peripheral)
            let register = StackRegister.connectingRegister(forPeripheral: configuration.peripheral, onError: onError)
            addConnectingPeripheral(configuration.peripheral)
            insertInRegistry(register)
            centralSession?.connectToPeripheral(connectionConfiguration: configuration)
        } catch {
            onError(error)
        }
    }
    
    /// A method that allows for the canceling of a connection to a given peripheral
    public func cancelConnectionToPeripheral(_ peripheral: CBPeripheral, onError: @escaping (Error) -> Void) {
        do {
            try verifySystemState()
            try checkRegistry(doesNotContainInstruction: .disconnecting, forAddressee: peripheral)
            guard peripheralIsInConnected(peripheral) || peripheralIsInConnecting(peripheral)
            else {
                onError(StackError.unknownDevice)
                return
            }
            
            let disconnectRegistryEntry = StackRegister.disconnectingRegister(forPeripheral: peripheral, onError: onError)
            if peripheralIsInConnecting(peripheral) {
                removeConnectingPeripheral(peripheral)
                insertInRegistry(disconnectRegistryEntry)
                centralSession?.cancelConnection(toPeripheral: peripheral)
            }
            else if peripheralIsInConnected(peripheral) {
                removeConnectedPeripheral(peripheral)
                insertInRegistry(disconnectRegistryEntry)
                centralSession?.cancelConnection(toPeripheral: peripheral)
            }
        } catch {
            onError(error)
        }
    }
    
    /// A method that allows for the reconnecting to a perviously known peripheral
    public func reconnectToPeripheral(withConfiguration configuration: ReconnectConfiguration, onError: @escaping (Error) -> Void) {
        do {
            try verifySystemState()
            let peripheral = try findPeripheralToReconnect(configuration.peripheralIdentifier, services: configuration.peripheralServiceIdentifiers)
            let connectConfiguration = configuration.createConnectionConfiguration(forPeripheral: peripheral)
            connectPeripheral(withConfiguration: connectConfiguration, onError: onError)
        } catch {
            onError(error)
        }
    }
}

// MARK: - Connections
extension BluetoothStack {
    struct SetValueConnection<Value>: Connector
    where Value: Equatable
    {
        typealias Element = Value
        
        let value: Value?
        
        func connect() -> Output {
            Just(value)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
    }
}

// MARK: - Formatters
extension BluetoothStack {
    private static func systemReady(from state: CBManagerState?) -> SystemReady {
        state == .poweredOn
    }
    
    fileprivate static var systemReadyFormat = Format(format: systemReady)
    
    fileprivate static func formatForSystemReady(basedOn stateKernel: Kernel<CBManagerState>, toManager manager: Manager<SystemReady>) {
        let systemReadySource = stateKernel
            .whenValueUpdates()
            .formatUsing(BluetoothStack.systemReadyFormat)
            .map { Optional<SystemReady>($0) }
            .eraseToAnyPublisher()
        
        manager.whenFormattedValueReceived(from: systemReadySource)
    }
}

extension BluetoothStack {
    private static func systemScanning(from registry: [StackRegister]?) -> SystemScanning {
        registry?.contains(where: { $0.instruction == .scanning }) == true
    }
    
    fileprivate static var systemScanningFormat = Format(format: systemScanning)
    
    fileprivate static func formatForSystemScanning(basedOn registryKernel: Kernel<Registry>, toManager manager: Manager<SystemScanning>) {
        let systemScanningSource = registryKernel
            .whenValueUpdates()
            .formatUsing(BluetoothStack.systemScanningFormat)
            .map { Optional<SystemScanning>($0) }
            .eraseToAnyPublisher()
        
        manager.whenFormattedValueReceived(from: systemScanningSource)
    }
}

extension BluetoothStack {
    private static func discoveredPeripherals(_ peripherals: DiscoveredPeripherals?) -> AvailablePeripherals {
        let items = peripherals ?? []
        return items.sorted().reversed()
    }
    
    fileprivate static var discoveredPeripheralsFormat = Format(format: discoveredPeripherals)
    
    fileprivate static func formatForDiscoveredPeripherals(basedOn discoveryKernel: Kernel<DiscoveredPeripherals>, toManager manager: Manager<AvailablePeripherals>) {
        let peripheralSource = discoveryKernel
            .whenValueUpdates()
            .formatUsing(discoveredPeripheralsFormat)
            .map { Optional<AvailablePeripherals>($0) }
            .eraseToAnyPublisher()
        
        manager.whenFormattedValueReceived(from: peripheralSource)
    }
}

extension BluetoothStack {
    private static func connectingPeripherals(_ peripherals: ConnectedSystemPeripherals?) -> ConnectedPeripherals {
        let connecting = peripherals ?? []
        let items = Array(connecting)
        return items
    }
    
    fileprivate static var connectingPeripheralsFormat = Format(format: connectingPeripherals)
    
    fileprivate static func formatForConnectingPeripherals(basedOn connectingKernel: Kernel<ConnectedSystemPeripherals>, toManager manager: Manager<ConnectedPeripherals>) {
        let source = connectingKernel
            .whenValueUpdates()
            .formatUsing(connectingPeripheralsFormat)
            .map { Optional<ConnectedPeripherals>($0) }
            .eraseToAnyPublisher()
        
        manager.whenFormattedValueReceived(from: source)
    }
}

extension BluetoothStack {
    private static func connectedPeripherals(_ peripherals: ConnectedSystemPeripherals?) -> ConnectedPeripherals {
        let connected = peripherals ?? []
        let items = Array(connected)
        return items
    }
    
    fileprivate static var connectedPeripheralsFormat = Format(format: connectedPeripherals)
    
    fileprivate static func formatForConnectedPeripherals(basedOn connectedKernel: Kernel<ConnectedSystemPeripherals>, toManager manager: Manager<ConnectedPeripherals>) {
        let source = connectedKernel
            .whenValueUpdates()
            .formatUsing(connectedPeripheralsFormat)
            .map { Optional<ConnectedPeripherals>($0) }
            .eraseToAnyPublisher()
        
        manager.whenFormattedValueReceived(from: source)
    }
}
