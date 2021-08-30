# BluetoothStack

A system to interact with Bluetooth peripherals.

This system is an application layer stack that sits on top of Apple's Core Bluetooth APIs. 

The goals of this system is:

* Provide a Combine interface for Bluetooth system status & authorization states
* Provide a simplified interface to troubleshoot the system
* Provide a simplified interface to scan for peripherals with simplified error reporting
* Provide a Combine interface for available peripherals to connect to
* Provide a Combine interface to manage connected peripherals
* Provide a Combine interface to monitor connecting peripherals
* Provide a simplified interface to connect to a peripheral
* Provide a interface to disconnect / cancel connection to peripheral

## Components

- BluetoothStack

An object that is responsible to provide a public interface for peripheral connections, and troubleshooting.

The bluetooth stack will report events via publishers.

## Using BluetoothStack

When entering a flow that uses the stack, initialize and maintain a reference to the stack instance.

In general the following steps are required when interacting with the stack:

1. When ready to start interacting with the bluetooth system call: `initializeSession(with:)` method to start a bluetooth session. Calling this method will cause iOS to prompt the user with any prompts and additionally any configured prompts.
2. Monitor `systemStatusPublisher` for the system status
3. Perform `startScanning(for: onError:)` to scan for peripherals advertising nearby.
4. Monitor `systemScanningPublisher` for the scan status
5. Perform `stopScanning(onError:)` to stop scanning for peripherals.
6. Monitor `availablePeripheralPublisher` for the available peripherals discovered while scanning.
7. Perform `connectPeripheral(withConfiguration: onError:)` to connect to a given peripheral with a configuration - or - `reconnectToPeripheral(withConfiguration: onError:)` to reconnect
8. Monitor `connectingPeripheralsPublisher` for a current list of connecting peripherals
9. Monitor `connectedPeripheralPublisher` for a current list of connected peripherals
10. Perform `cancelConnectionToPeripheral(: onError:)` to cancel a connection to a peripheral

```
Initialize Stack ---------> Application UI
|                           |
|                           |
|                           v
|                           When Ready
|                           |
|                           |
|                           v
|                           Initialize Session
|                           |
|                           |
|                           v
|                           Start Scan
|                           |
|                           |
|                           v
|                           Stop Scan
|                           |
|                           |
|                           v
|                           Connect to Peripheral / or Reconnect to Peripheral
|                           |
|                           |
|                           v
|                           Cancel Connection to Peripheral
|
|
v
Monitor system ready publisher
|
|
|
Monitor system scanning publisher
|
|
|
Monitor available peripheral publisher
|
|
|
Monitor connecting peripheral publisher
|
|
|
Monitor connected peripheral publisher
|
|
v
```

## Understanding System Status

Responding to system status can be handled via the `systemReadyPublisher` on `BluetoothStack` object. The system ready publisher will report a `Bool` type to indicate if the system is ready for use.

```
let stack = BluetoothStack()

/// observe state
stack
    .systemReadyPublisher
    .sink { systemReady in 
        // systemReady is a `Bool` value to indicate that the stack is ready for use
    }
```

The output of the publisher is defined as follows:

```
+-
|
| poweredOff
| poweredOn
| resetting      --------> CentralManagerState  --------> isPoweredOn -------> SystemReady
| unauthorized
| unknown
| unsupported
|
+-
```

### Troubleshooting System Status

By design the `systemReadyPublisher` emits a simplified value. In the event that the system is reported to be not ready the `BluetoothStack` exposes an API that allows for developers to query the system for detailed diagnostic information. The stack has a method `troubleshootSystemReady` that will return a `SystemReadyTroubleshooting` type. This reports the `CBManagerState` and the `CBManagerAuthorization` values for the system.

To understand how this can be accomplished:

```
let stack = BluetoothStack()
let telemetry = stack.troubleshootSystemReady()
let systemState = telemetry.systemState
let authorizationState = telemetry.authorizationState
```

These values are preserved types from `CoreBluetooth` and give granular data on why the system may not be ready for use. Users can use this information to present custom UI as needed.

## Understanding System Scanning

Responding to system scanning can be handled via the `systemScanningPublisher` on `BluetoothStack` object. The system scanning publisher will report a `Bool` type to indicate if the system is actively scanning for peripherals.

```
let stack = BluetoothStack()

/// observe state
stack
    .systemScanningPublisher
    .sink { systemScanning in 
        // systemScanning is a `Bool` value to indicate activity
    }
}
```

### Starting a scan

Starting a scan can be accomplished by the following method on `BluetoothStack`, `startScanning(for: onError:)`.

When scanning errors can be thrown for the following reasons:

1. the system is not in a ready state (see system status for more information)
2. the system is already scanning

When starting to scan for peripherals, the method requires a `ScanConfiguration` object. This informs the system what devices the application is interested in finding, and how that device should be reported to the application.

### Stopping a scan

Stopping a scan can be accomplished by the following method on `BluetoothStack`, `stopScanning(onError:)`.

Stopping a scan can throw an error for the following reasons:

1. the system is not currently scanning

### Available Peripherals

A `availablePeripheralPublisher` is available on the `BluetoothStack` object that can be monitored.

For example:

```
let stack = BluetoothStack()

/// observe available peripherals
stack
    .availablePeripheralPublisher
    .sink { availablePeripherals in
        // availablePeripherals is a collection of discovered peripherals sorted by their RSSI values.
    }
```

## Understanding Peripheral Connection

Responding to peripherals the system is attempting to connect can be handled via the `connectingPeripheralPublisher` on the `BluetoothStack` object. This will provide a current list of peripherals that the system is attempting to establish a connection to. It is import to understand that the attempt to establish a connection to a peripheral will not time out, and thus will need to be handled via the application if desired.

Responding to peripherals that are currently connected to the system can be handled via the `connectedPeripheralPublisher` on the `BluetoothStack` object. This will provide a list of currently connected peripheral objects.

```
let stack = BluetoothStack()

stack
    .connectingPeripheralPublisher
    .sink { connectingPeripherals in 
        // connectingPeripherals is a collection of peripheral currently being connected to
    }
    
stack
    .connectedPeripheralPublisher
    .sink { connectedPeripherals in 
        // connectedPeripherals is a collection of peripherals currently connected by the system
    }
```

### Connecting to a Peripheral

Connecting to a peripheral is accomplished by first creating a `ConnectionConfiguration` object. This object is responsible for setting basic connection settings for a given peripheral. Then call the `connectPeripheral(withConfiguration: onError:)` method on `BluetoothStack` object. Success will be reported via the `connectedPeripheralPublisher` and an error will be reported via the `onError` parameter of the method. 

Given connecting to a peripheral does not time out, errors thrown are generally transient and is best to attempt again.

### Canceling Connection to a Peripheral

Canceling a connection to a peripheral is accomplished by calling the `cancelConnectionToPeripheral(: onError:)` method on the `BluetoothStack` object. Success will be reported by the `connectedPeripheralPublisher` updating with a new list of currently connected peripherals, and an error will be reported via the `onError` parameter of the method.

Canceling serves two important functions for a peripheral, first if a peripheral is currently pending a connection with the system this serves to stop the pending attempt, and second will disconnect the peripheral if a connection has been established. It is important to note that the iOS system manages connections to a given peripheral and not the application layer used by CoreBluetooth. Thus, canceling a connection is only from the perspective of the application layer and does not force a disconnect from the iOS system. 

### Reconnecting to a Peripheral

Reconnecting to a peripheral is accomplished by first creating a `ReconnectConfiguration` object. This object is responsible for setting basic connection settings for a given peripheral, and in addition required identifiers for identifying a peripheral to connect. Then call the `reconnectToPeripheral(withConfiguration: onError:)` method on `BluetoothStack` object. Success will be reported via the `connectedPeripheralPublisher` and an error will be reported via the `onError` parameter of the method. 

In order to reconnect to a peripheral, two things are needed:

1. The identifier assigned by CoreBluetooth for the peripheral
2. The service identifiers needed on the peripheral

Identifiers assigned to a device are managed by CoreBluetooth and are safe to persist between sessions on a single device.

General methodology to reconnect a peripheral:

```
+-
|
|   check for peripheral with identifier
|   |
|   |
|   v
|   is found    -->     connect (see connecting above)
|   |
|   |
|   v
|   check for any system peripherals with service identifiers
|   |
|   |
|   v
|   is found    -->     connect (see connecting above)
|   |
|   |
|   v
|   if none found throw unknown device error
|
+-
```
