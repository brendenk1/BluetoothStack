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
    
    fileprivate typealias DiscoveredPeripherals = Set<DiscoveredPeripheral>
    fileprivate typealias Registry = Array<StackRegister>
    
    private var centralSession: BluetoothCentralSession?
    
    // Kernels
    private let systemState: Kernel<CBManagerState> = Kernel()
    private let systemRegister: Kernel<Registry> = Kernel()
    private let systemDiscoveredPeripherals: Kernel<DiscoveredPeripherals> = Kernel()
    
    // Managers
    private let systemReady: Manager<SystemReady> = Manager()
    private let systemScanning: Manager<SystemScanning> = Manager()
    private let systemPeripherals: Manager<AvailablePeripherals> = Manager()
    
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
    
    // Formatted Values
    private func configureFormattingForManagers() {
        BluetoothStack.formatForSystemReady(basedOn: systemState, toManager: systemReady)
        BluetoothStack.formatForSystemScanning(basedOn: systemRegister, toManager: systemScanning)
        BluetoothStack.formatForDiscoveredPeripherals(basedOn: systemDiscoveredPeripherals, toManager: systemPeripherals)
    }
    
    // Helpers
    fileprivate func verifySystemState() throws {
        if (systemState.currentValue == .poweredOn) == false {
            throw StackError.systemNotReady
        }
    }
    
    fileprivate func checkRegistry(doesNotContainInstruction instruction: StackRegister.Instruction) throws {
        if systemRegister.currentValue?.contains(where: { $0.instruction == instruction }) == true {
            throw StackError.invalidInstruction
        }
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
                                                 onPeripheralDiscovered: { [weak self] discoveredPeripheral in self?.onPeripheralDiscovery(discoveredPeripheral) })
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
