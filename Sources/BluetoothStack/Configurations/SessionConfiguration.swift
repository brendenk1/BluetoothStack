import CoreBluetooth
import Foundation

/*
 Configuration settings for a session of the `CBCentralManager` object
 
 For example:
 
 When initializing a `CBCentralManager` object, the system can display an alert to the user if the radio is powered off.
 */
public struct SessionConfiguration {
    /// A flag to indicate if the system should display an alert if the radio is powered off
    let showPowerAlertIfNeeded: Bool
    
    static var standard: SessionConfiguration = SessionConfiguration(showPowerAlertIfNeeded: false)
    
    /// Options used by Core Bluetooth Central Manager objects
    var options: [String: Any] {
        [
            CBCentralManagerOptionShowPowerAlertKey: NSNumber(booleanLiteral: showPowerAlertIfNeeded)
        ]
    }
}
