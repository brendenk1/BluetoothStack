import Combine
import CoreBluetooth
import Foundation
import Synthesis

/// An object responsible for managing the `Bluetooth` stack
///
/// Currently the stack is only designed for `Central` management and does not support background modes.
public final class BluetoothStack {
    public init() {
        configureFormattingForManagers()
    }
    
    public typealias SystemReady = Bool
    public typealias SystemReadyTroubleshooting = (systemState: CBManagerState?, authorizationState: CBManagerAuthorization)
    
    private var centralSession: BluetoothCentralSession?
    
    // Kernels
    private let systemState: Kernel<CBManagerState> = Kernel()
    private let systemReady: Manager<SystemReady> = Manager()
    
    // Actions
    fileprivate func onStateChange(_ state: CBManagerState) {
        Action(connector: SetValueConnection(value: state),
               kernel: systemState)
            .execute()
    }
    
    // Formatted Values
    private func configureFormattingForManagers() {
        let systemReadySource = systemState
            .whenValueUpdates()
            .formatUsing(BluetoothStack.systemReadyFormat)
            .map { Optional<SystemReady>($0) }
            .eraseToAnyPublisher()
        
        systemReady.whenFormattedValueReceived(from: systemReadySource)
    }
}

// MARK: - Public Interface
extension Bool: Identifiable {
    public var id: Bool {
        self
    }
}

extension BluetoothStack {
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
                                                 onStateChange: { [weak self] state in self?.onStateChange(state) })
    }
    
    /// A function to troubleshoot if a system is not `ready`
    ///
    /// The `CBManagerState` will be reported as `nil` until the session is initialized
    public func troubleshootSystemReady() -> SystemReadyTroubleshooting {
        (systemState.currentValue, CBManager.authorization)
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
    
    static var systemReadyFormat = Format(format: systemReady)
}
