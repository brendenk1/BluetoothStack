# BluetoothStack

A system to interact with Bluetooth peripherals.

This system is an application layer stack that sits on top of Apple's Core Bluetooth APIs. 

The goals of this system is:

* Provide a Combine interface for Bluetooth system status & authorization states
* Provide a simplified interface to troubleshoot the system

## Components

- BluetoothStack

An object that is responsible to provide a public interface for peripheral connections, and troubleshooting.

The bluetooth stack will report events via publishers.

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
