import CoreBluetooth
import Foundation

/*
 Configuration settings to perform a scan
 
 For example:
 
 It is recommended by `CoreBluetooth` to only perform scans for peripherals with known Service identifiers in an advertising packet. Passing a collection of service identifiers as `CBUUID` objects informs the system what peripherals the application is interested in.
 
 It is recommended by `CoreBluetooth` to only update for unique peripheral advertising packets. If the application context wants to receive all advertising packets, passing `true` will accommodate this. Be aware that this has severe negative implications on performance.
 
 ```
 // This example will search for peripherals advertising the service identifier with "001A", and will only report once during the scan process.
 let configuration = ScanConfiguration(serviceIdentifiers: [CBUUID(string: "001A")], reportDuplicatePeripherals: false)
 ```
 */
public struct ScanConfiguration {
    public init(serviceIdentifiers: [CBUUID]?, reportDuplicatePeripherals: Bool) {
        self.serviceIdentifiers = serviceIdentifiers
        self.reportDuplicatePeripherals = reportDuplicatePeripherals
    }
    
    let serviceIdentifiers: [CBUUID]?
    let reportDuplicatePeripherals: Bool
}

extension ScanConfiguration {
    var options: [String: Any] {
        [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(booleanLiteral: reportDuplicatePeripherals)
        ]
    }
}
