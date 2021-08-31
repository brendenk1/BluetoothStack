import CoreBluetooth
import Foundation

public struct ConnectionConfiguration {
    public typealias Service = CBUUID
    public typealias Characteristic = CBUUID
    public typealias ConnectionRoutes = [Service: [Characteristic]]
    
    public init(peripheral: CBPeripheral, connectionRoutes: ConnectionRoutes, displayAlertOnBackgroundConnect: Bool, displayAlertOnBackgroundDisconnect: Bool, displayAlertOnNotificationReceived: Bool, bridgeToClassicBluetooth: Bool, connectionRequiresACNS: Bool, connectionStartDelay: Int) {
        self.peripheral = peripheral
        self.connectionRoutes = connectionRoutes
        self.displayAlertOnBackgroundConnect = displayAlertOnBackgroundConnect
        self.displayAlertOnBackgroundDisconnect = displayAlertOnBackgroundDisconnect
        self.displayAlertOnNotificationReceived = displayAlertOnNotificationReceived
        self.bridgeToClassicBluetooth = bridgeToClassicBluetooth
        self.connectionRequiresACNS = connectionRequiresACNS
        self.connectionStartDelay = connectionStartDelay
    }
    
    /// The device to connect to
    let peripheral: CBPeripheral
    /// The route to discover on the device
    let connectionRoutes: ConnectionRoutes
    /// A Boolean value that specifies whether the system should display an alert when connecting a peripheral in the background.
    let displayAlertOnBackgroundConnect: Bool
    /// A Boolean value that specifies whether the system should display an alert when disconnecting a peripheral in the background.
    let displayAlertOnBackgroundDisconnect: Bool
    /// A Boolean value that specifies whether the system should display an alert for any notification sent by a peripheral. (While the app is suspended)
    let displayAlertOnNotificationReceived: Bool
    /// An option to bridge classic Bluetooth technology profiles, if already connected over Bluetooth Low Energy.
    let bridgeToClassicBluetooth: Bool
    /// An option to require Apple Notification Center Service (ANCS) when connecting a device.
    let connectionRequiresACNS: Bool
    /// An option that indicates a delay before the system makes a connection. (In seconds)
    let connectionStartDelay: Int
    
    public static func standardConfiguration(forPeripheral peripheral: CBPeripheral, connectionRoutes: ConnectionRoutes) -> ConnectionConfiguration {
        ConnectionConfiguration(peripheral: peripheral,
                                connectionRoutes: connectionRoutes,
                                displayAlertOnBackgroundConnect: false,
                                displayAlertOnBackgroundDisconnect: false,
                                displayAlertOnNotificationReceived: false,
                                bridgeToClassicBluetooth: false,
                                connectionRequiresACNS: false,
                                connectionStartDelay: 0)
    }
}

// MARK: - Bluetooth Session
extension ConnectionConfiguration {
    /// The options used by the bluetooth session when connection a peripheral object.
    var options: [String: Any] {
        var connectOptions: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: NSNumber(booleanLiteral: displayAlertOnBackgroundConnect),
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: NSNumber(booleanLiteral: displayAlertOnBackgroundDisconnect),
            CBConnectPeripheralOptionNotifyOnNotificationKey: NSNumber(booleanLiteral: displayAlertOnNotificationReceived),
            CBConnectPeripheralOptionStartDelayKey: NSNumber(integerLiteral: connectionStartDelay)
        ]
        
        #if !os(macOS)
        connectOptions[CBConnectPeripheralOptionEnableTransportBridgingKey] = NSNumber(booleanLiteral: bridgeToClassicBluetooth)
        connectOptions[CBConnectPeripheralOptionRequiresANCS] = NSNumber(booleanLiteral: connectionRequiresACNS)
        #endif
        
        return connectOptions
    }
}
