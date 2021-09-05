import Combine
import CoreBluetooth
import Foundation
import Synthesis

/// An object responsible for managing the `Bluetooth` stack
///
/// Currently the stack is only designed for `Central` management and does not support background modes.
public final class BluetoothStack: NSObject, ObservableObject {
    public override init() {
        super.init()
        configureFormattingForManagers()
    }
    
    public typealias WhenError = (Error) -> Void
    public typealias SystemReady = Bool
    public typealias SystemReadyTroubleshooting = (systemState: CBManagerState?, authorizationState: CBManagerAuthorization)
    public typealias SystemScanning = Bool
    public typealias AvailablePeripherals = Array<DiscoveredPeripheral>
    public typealias ConnectedPeripherals = Array<CBPeripheral>
    public typealias KnownPaths = Array<KnownPath>
    
    fileprivate typealias DiscoveredPeripherals = Set<DiscoveredPeripheral>
    fileprivate typealias ConnectedSystemPeripherals = Set<CBPeripheral>
    fileprivate typealias Registry = Array<StackRegister>
    
    private var centralSession: BluetoothCentralSession?
    private var discoveries = Set<PeripheralPathDiscoverer>()
    private var connectionSubscriptions = Set<AnyCancellable>()
    
    // Register
    private let register: Register<StackRegister> = Register()
    
    // Kernels
    private let systemState: Kernel<CBManagerState> = Kernel()
    private let systemDiscoveredPeripherals: Kernel<DiscoveredPeripherals> = Kernel()
    private let systemConnectingPeripherals: Kernel<ConnectedSystemPeripherals> = Kernel()
    private let systemConnectedPeripherals: Kernel<ConnectedSystemPeripherals> = Kernel()
    private let systemPaths: Kernel<KnownPaths> = Kernel()
    
    // Managers
    private let systemReady: Manager<SystemReady> = Manager()
    private let systemScanning: Manager<SystemScanning> = Manager()
    private let systemPeripherals: Manager<AvailablePeripherals> = Manager()
    private let connectingPeripherals: Manager<ConnectedPeripherals> = Manager()
    private let connectedPeripherals: Manager<ConnectedPeripherals> = Manager()
    
    // Actions
    fileprivate func onStateChange(_ state: CBManagerState) {
        Action(connector: SetValueConnector(value: state),
               kernel: systemState)
            .execute()
    }
    
    fileprivate func onPeripheralDiscovery(_ discoveredPeripheral: DiscoveredPeripheral) {
        var discoveredPeripherals = systemDiscoveredPeripherals.currentValue ?? Set()
        discoveredPeripherals.update(with: discoveredPeripheral)
        Action(connector: SetValueConnector(value: discoveredPeripherals),
               kernel: systemDiscoveredPeripherals)
            .execute()
    }
    
    fileprivate func onConnectionEvent(_ connectionEvent: BluetoothCentralSession.ConnectionEvent) {
        do {
            switch connectionEvent {
            case .success(let peripheral):
                let registryItem = try findAddresseeInRegistry(peripheral, forInstruction: .connecting)
                let discovery = PeripheralPathDiscoverer(forPeripheral: peripheral)
                discovery.discoverPaths(forConfiguration: registryItem.addressee?.connectionRoutes)
                    .sink(receiveCompletion: { [unowned self] completion in
                        if case let .failure(error) = completion {
                            register.removeFromRegister(element: registryItem)
                            registryItem.addressee?.onError(error)
                            cancelConnectionToPeripheral(peripheral, onError: registryItem.addressee?.onError ?? { _ in })
                        }
                    },
                          receiveValue: { [unowned self] paths in
                        addPaths(paths)
                        discoveries.remove(discovery)
                        register.removeFromRegister(element: registryItem)
                        removeConnectingPeripheral(peripheral)
                        addConnectedPeripheral(peripheral)
                    })
                    .store(in: &connectionSubscriptions)
                discoveries.insert(discovery)
            case .failure(let connectionError):
                let registryItem = try findAddresseeInRegistry(connectionError.peripheral, forInstruction: .connecting)
                register.removeFromRegister(element: registryItem)
                registryItem.addressee?.onError(connectionError)
            }
        } catch {
            print("*** API MISUSE \(error)")
        }
        
    }
    
    fileprivate func onDisconnectionEvent(_ disconnectionEvent: BluetoothCentralSession.DisconnectionEvent) {
        switch disconnectionEvent {
        case .success(let peripheral):
            if let connectionRegistryItem = try? findAddresseeInRegistry(peripheral, forInstruction: .connecting) {
                register.removeFromRegister(element: connectionRegistryItem)
            }
            if let disconnectRegistryItem = try? findAddresseeInRegistry(peripheral, forInstruction: .disconnecting) {
                register.removeFromRegister(element: disconnectRegistryItem)
            }
            clearPaths(forPeripheral: peripheral)
        case .failure(let disconnectionError):
            if let connectionRegistryItem = try? findAddresseeInRegistry(disconnectionError.peripheral, forInstruction: .connecting) {
                register.removeFromRegister(element: connectionRegistryItem)
                connectionRegistryItem.addressee?.onError(disconnectionError)
            }
            if let disconnectRegistryItem = try? findAddresseeInRegistry(disconnectionError.peripheral, forInstruction: .disconnecting) {
                register.removeFromRegister(element: disconnectRegistryItem)
                disconnectRegistryItem.addressee?.onError(disconnectionError)
            }
            clearPaths(forPeripheral: disconnectionError.peripheral)
        }
    }
    
    // Formatted Values
    private func configureFormattingForManagers() {
        BluetoothStack.formatForSystemReady(basedOn: systemState, toManager: systemReady)
        BluetoothStack.formatForSystemScanning(basedOn: register, toManager: systemScanning)
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
        guard register.contains(byMatching: { $0.instruction == instruction }) == false
        else { throw StackError.invalidInstruction }
    }

    fileprivate func checkRegistry(doesNotContainInstruction instruction: StackRegister.Instruction, forAddressee addressee: CBPeripheral) throws {
        guard register.contains(byMatching: { item in
            item.hasPeripheralAddressee(addressee) &&
            item.instruction == instruction
        }) == false
        else { throw StackError.invalidInstruction }
    }

    fileprivate func checkRegistry(containsInstruction instruction: StackRegister.Instruction) throws {
        guard register.contains(byMatching: { $0.instruction == instruction })
        else { throw StackError.invalidInstruction }
    }

    fileprivate func findAddresseeInRegistry(_ peripheral: CBPeripheral, forInstruction instruction: StackRegister.Instruction) throws -> StackRegister {
        try register.findRegistryItem(byMatching: { item in
            item.hasPeripheralAddressee(peripheral) &&
            item.instruction == instruction
        })
    }
    
    // MARK: Connecting Peripherals
    fileprivate func addConnectingPeripheral(_ peripheral: CBPeripheral) {
        var connectingPeripherals = systemConnectingPeripherals.currentValue ?? []
        connectingPeripherals.update(with: peripheral)
        Action(connector: SetValueConnector(value: connectingPeripherals),
               kernel: systemConnectingPeripherals)
            .execute()
    }
    
    fileprivate func removeConnectingPeripheral(_ peripheral: CBPeripheral) {
        var connectingPeripherals = systemConnectingPeripherals.currentValue ?? []
        connectingPeripherals.remove(peripheral)
        Action(connector: SetValueConnector(value: connectingPeripherals),
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
        Action(connector: SetValueConnector(value: connectedPeripherals),
               kernel: systemConnectedPeripherals)
            .execute()
    }
    
    fileprivate func removeConnectedPeripheral(_ peripheral: CBPeripheral) {
        var connectedPeripherals = systemConnectedPeripherals.currentValue ?? []
        connectedPeripherals.remove(peripheral)
        Action(connector: SetValueConnector(value: connectedPeripherals),
               kernel: systemConnectedPeripherals)
            .execute()
    }
    
    fileprivate func peripheralIsInConnected(_ peripheral: CBPeripheral) -> Bool {
        systemConnectedPeripherals
            .currentValue?
            .contains(peripheral) == true
    }
    
    // MARK: Paths
    fileprivate func addPaths(_ paths: [KnownPath]) {
        var currentPaths = systemPaths.currentValue ?? []
        currentPaths.append(contentsOf: paths)
        Action(connector: SetValueConnector(value: currentPaths),
               kernel: systemPaths)
            .execute()
    }
    
    fileprivate func clearPaths(forPeripheral peripheral: CBPeripheral) {
        var currentPaths = systemPaths.currentValue ?? []
        let pathsForPeripheral = currentPaths.filter { $0.peripheral == peripheral }
        pathsForPeripheral.forEach { path in
            if let index = currentPaths.firstIndex(of: path) {
                currentPaths.remove(at: index)
            }
        }
        Action(connector: SetValueConnector(value: currentPaths),
               kernel: systemPaths)
            .execute()
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
            register.updateRegister(withElement: .scanningRegister)
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
            register.removeFromRegister(element: .scanningRegister)
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
    public func connectPeripheral(withConfiguration configuration: ConnectionConfiguration, onError: @escaping WhenError) {
        do {
            try verifySystemState()
            try checkRegistry(doesNotContainInstruction: .connecting, forAddressee: configuration.peripheral)
            let registryItem = StackRegister.connectingRegister(forPeripheral: configuration.peripheral, connectionRoutes: configuration.connectionRoutes, onError: onError)
            addConnectingPeripheral(configuration.peripheral)
            register.updateRegister(withElement: registryItem)
            centralSession?.connectToPeripheral(connectionConfiguration: configuration)
        } catch {
            onError(error)
        }
    }
    
    /// A method that allows for the canceling of a connection to a given peripheral
    public func cancelConnectionToPeripheral(_ peripheral: CBPeripheral, onError: @escaping WhenError) {
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
                register.updateRegister(withElement: disconnectRegistryEntry)
                centralSession?.cancelConnection(toPeripheral: peripheral)
            }
            else if peripheralIsInConnected(peripheral) {
                removeConnectedPeripheral(peripheral)
                register.updateRegister(withElement: disconnectRegistryEntry)
                centralSession?.cancelConnection(toPeripheral: peripheral)
            }
        } catch {
            onError(error)
        }
    }
    
    /// A method that allows for the reconnecting to a perviously known peripheral
    public func reconnectToPeripheral(withConfiguration configuration: ReconnectConfiguration, onError: @escaping WhenError) {
        do {
            try verifySystemState()
            let peripheral = try findPeripheralToReconnect(configuration.peripheralIdentifier, services: configuration.peripheralServiceIdentifiers)
            let connectConfiguration = configuration.createConnectionConfiguration(forPeripheral: peripheral)
            connectPeripheral(withConfiguration: connectConfiguration, onError: onError)
        } catch {
            onError(error)
        }
    }
    
    /// A method that allows for the finding of paths for services and characteristics on a given peripheral
    public func path(forPeripheralIdentifier peripheral: UUID, serviceIdentifier service: CBUUID, characteristicIdentifier characteristic: CBUUID) throws -> CBCharacteristic {
        let foundPath = systemPaths
            .currentValue?
            .filter { $0.pathFor(peripheral, service: service, characteristic: characteristic) }
            .first
            .map { $0.characteristic }
        guard let foundPath = foundPath
        else {
            throw StackError.unknownPath
        }
        return foundPath
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
    private static func systemScanning(from registry: [StackRegister]) -> SystemScanning {
        registry.contains(where: { $0.instruction == .scanning }) == true
    }
    
    fileprivate static var systemScanningFormat = Format(format: systemScanning)
    
    fileprivate static func formatForSystemScanning(basedOn registry: Register<StackRegister>, toManager manager: Manager<SystemScanning>) {
        let systemScanningSource = registry
            .publisher
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
