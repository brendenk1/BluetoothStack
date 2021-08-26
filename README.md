# BluetoothStack

A system to interact with Bluetooth peripherals.

This system is an application layer stack that sits on top of Apple's Core Bluetooth APIs. 

The goals of this system is:

* Provide a Combine interface for Bluetooth system status & authorization states
* Provide a simplified interface to troubleshoot the system
* Provide a simplified interface to scan for peripherals with simplified error reporting

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
|
v
Monitor system ready publisher
|
|
|
Monitor system scanning publisher
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
| poweredOn                                               
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
let state = BluetoothStack()

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
