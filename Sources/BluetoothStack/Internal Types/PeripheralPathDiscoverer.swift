import Combine
import CoreBluetooth
import Foundation

final class PeripheralPathDiscoverer: NSObject, CBPeripheralDelegate {
    init(forPeripheral peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }
    
    private let peripheral: CBPeripheral
    private var routes: ConnectionConfiguration.ConnectionRoutes?
    private var pendingServices: Set<CBService> = Set()
    private let whenComplete = PassthroughSubject<[KnownPath], Error>()
    
    private func mapCharacteristics() {
        var knownPaths: [KnownPath] = []
        
        peripheral.services?.forEach { service in
            service.characteristics?.forEach { characteristic in
                knownPaths.append(KnownPath(peripheral: peripheral, service: service, characteristic: characteristic))
            }
        }
        
        whenComplete.send(knownPaths)
        whenComplete.send(completion: .finished)
    }
    
    func discoverPaths(forConfiguration routes: ConnectionConfiguration.ConnectionRoutes?) -> AnyPublisher<[KnownPath], Error> {
        self.routes = routes
        let serviceIdentifiers = routes?.keys.map { $0 }
        peripheral.discoverServices(serviceIdentifiers)
        return whenComplete.eraseToAnyPublisher()
    }
    
    // MARK: Delegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral == peripheral
        else { return }
        if let error = error {
            whenComplete.send(completion: .failure(error))
        } else {
            self.pendingServices = Set(peripheral.services ?? [])
            peripheral.services?.forEach { service in
                if let characteristics = routes?[service.uuid] {
                    peripheral.discoverCharacteristics(characteristics, for: service)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral == peripheral
        else { return }
        pendingServices.remove(service)
        if let error = error {
            whenComplete.send(completion: .failure(error))
        } else {
            if pendingServices.isEmpty { mapCharacteristics() }
        }
    }
}
