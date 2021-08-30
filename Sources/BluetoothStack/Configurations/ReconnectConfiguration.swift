import CoreBluetooth
import Foundation

public struct ReconnectConfiguration {
    public init(peripheralIdentifier: UUID, peripheralServiceIdentifiers: [CBUUID], displayAlertOnBackgroundConnect: Bool, displayAlertOnBackgroundDisconnect: Bool, displayAlertOnNotificationReceived: Bool, bridgeToClassicBluetooth: Bool, connectionRequiresACNS: Bool, connectionStartDelay: Int) {
        self.peripheralIdentifier = peripheralIdentifier
        self.peripheralServiceIdentifiers = peripheralServiceIdentifiers
        self.displayAlertOnBackgroundConnect = displayAlertOnBackgroundConnect
        self.displayAlertOnBackgroundDisconnect = displayAlertOnBackgroundDisconnect
        self.displayAlertOnNotificationReceived = displayAlertOnNotificationReceived
        self.bridgeToClassicBluetooth = bridgeToClassicBluetooth
        self.connectionRequiresACNS = connectionRequiresACNS
        self.connectionStartDelay = connectionStartDelay
    }
    
    /// The identifier for the peripheral that would like to reconnect
    let peripheralIdentifier: UUID
    /// The services provided by a device to look for
    let peripheralServiceIdentifiers: [CBUUID]
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
}

extension ReconnectConfiguration {
    func createConnectionConfiguration(forPeripheral peripheral: CBPeripheral) -> ConnectionConfiguration {
        ConnectionConfiguration(peripheral: peripheral,
                                displayAlertOnBackgroundConnect: displayAlertOnBackgroundConnect,
                                displayAlertOnBackgroundDisconnect: displayAlertOnBackgroundDisconnect,
                                displayAlertOnNotificationReceived: displayAlertOnNotificationReceived,
                                bridgeToClassicBluetooth: bridgeToClassicBluetooth,
                                connectionRequiresACNS: connectionRequiresACNS,
                                connectionStartDelay: connectionStartDelay)
    }
}
