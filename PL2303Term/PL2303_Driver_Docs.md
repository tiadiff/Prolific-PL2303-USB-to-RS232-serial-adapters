# PL2303 User-Space Driver Implementation Guide

## Overview
This document details the reverse-engineering and implementation of a **native User-Space Driver** for Prolific PL2303 USB-to-Serial adapters on macOS 15.
This solution circumvents the need for kernel extensions (`.kext`) or System Extensions (`.dext`), allowing the application to communicate directly with the hardware using the standard `IOKit` framework.

## Architecture

The solution uses a **Mixed-Language** approach:
1.  **Objective-C Core (`PL2303DriverCore`)**: Handles direct `IOKit` interaction, C-pointer manipulation, and hardware-level USB requests.
2.  **Swift Layer (`PL2303Driver`, `SerialConnection`)**: Handles high-level data streaming, concurrency, and UI binding.

---

## 1. Device Discovery

**Problem**: macOS 15 does not load a VCP (Virtual COM Port) driver for this specific PL2303 PID (`0x23c3`), so no `/dev/cu.usbserial` file is created.

**Solution**: usage of `IOKit` to scan for **raw USB devices** (`IOUSBHostDevice`) instead of Serial services.

### Discovery Logic
- **Service Matching**: We create a matching dictionary for `IOUSBHostDevice`.
- **Filtering**: We iterate through all USB devices and mutually exclude those that are not Prolific:
  - **Vendor ID**: `0x067B` (Prolific Technology, Inc.).
  - **Product ID**: `0x23C3` (Common PL2303 variant).

```swift
// SerialPortManager.swift
let usbMatcher = IOServiceMatching("IOUSBHostDevice")
// ...
if vendor == 0x067B {
    // Found raw device, no driver attached
}
```

---

## 2. Low-Level Driver (Objective-C)

We chose **Objective-C** for the low-level driver because Swift's interaction with C-macros (like `kIOUSBDeviceUserClientTypeID`) and pointer-to-pointer interfaces (`**IOUSBDeviceInterface`) is verbose and error-prone.

**File**: `PL2303DriverCore.m`

### Connection Sequence
1.  **Plugin Creation**: Use `IOCreatePlugInInterfaceForService` to create a plugin for the `io_service_t`.
2.  **Query Interface**: Get the `IOUSBDeviceInterface300` from the plugin.
3.  **Open Device**: Call `USBDeviceOpen()` (or `USBDeviceOpenSeize` to force claim).
4.  **Configuration**: Set active configuration to `1` via `SetConfiguration()`.

### Interface and Pipes
The driver iterates through available interfaces to find **Interface 0** (the data interface).
Once opened, it scans the endpoints (`GetPipeProperties`) to identify:
-   **Bulk IN Pipe**: For receiving data (Device -> Host).
-   **Bulk OUT Pipe**: For sending data (Host -> Device).

### Initialization Sequence (The "Magic" Explained)
The PL2303 is not a standard CDC-ACM device. It requires a specific vendor-command handshake to enable the bulk endpoints. Without this, the device will be enumerated but will silently discard all data sent to it.

The sequence we implemented corresponds to the **PL2303HX** (and compatible) startup:

| Step | Request Type | Request | Value | Index | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `0x40` (Vendor Out) | `1` | `0x0404` | `0` | **Write Register 0**: Unknown proprietary setup (referenced in Linux `pl2303.c` as `PL2303_HX_INIT`). |
| 2 | `0x40` (Vendor Out) | `1` | `0x0404` | `1` | **Write Register 1**: Confirms the previous write. |

*Note: There are other variants (PL2303H, X, HX, TA) that use slightly different values (e.g., `0x0404` vs `0x0000`), but `0x0404` is the most compatible "safe mode" for the generic adapters found in the wild.*

### Baud Rate Configuration Schema
While many USB serial devices use the standard CDC `SET_LINE_CODING` structure, the PL2303 implements it as a **Class-Specific Request** rather than a standard Endpoint request.

**Packet Structure (7 Bytes):**
```c
struct {
    uint32_t dterate; // Baud Rate (Little Endian)
    uint8_t  charformat; // 0=1 stop bit, 1=1.5, 2=2
    uint8_t  paritytype; // 0=None, 1=Odd, 2=Even, 3=Mark, 4=Space
    uint8_t  databits;   // 5, 6, 7, 8
} line_coding;
```

**The Trap**: Standard drivers send this to the *End Point*. PL2303 expects it sent to the *Interface* (Interface `0`).
- **RequestType**: `0x21` (Class | Interface | Out)
- **Request**: `0x20` (SET_LINE_CODING)
- **Index**: `0` (Interface Number)

### What we simplified (The "Missing" Parts)
A full kernel driver is more complex because it handles:
1.  **Interrupt Pipe**: We are ignoring the Interrupt IN endpoint. This endpoint sends status updates for **DCD** (Data Carrier Detect), **RI** (Ring Indicator), and **DSR** (Data Set Ready). Since we only care about TX/RX data, we safely ignore this.
2.  **Flow Control**: Typically involves tweaking internal registers to enable RTS/CTS hardware flow control. We are relying on the chip's default behavior.
3.  **Error Handling**: A robust driver handles "Babble" errors and stalls by resetting the pipes (`ClearStall`). We implemented basic reconnection logic instead.

---

## 3. Data Reading & Concurrency

### Read Loop
Reading is performed on a background dispatch queue to avoid blocking the main thread.
-   **Method**: `startReadingWithBlock:`
-   **Mechanism**: Uses `ReadPipe()` in a `while` loop. This is a blocking synchronouse call that waits for data.
-   **Buffering**: Reads up to 64 bytes (Packet Size) at a time.
-   **Callback**: When data arrives, the Objective-C block is invoked with an `NSData` object.

### Swift Bridging (`PL2303Driver.swift`)
The Swift wrapper creates an `AsyncStream` to expose the data in a modern, Swift-concurrency-friendly way.

**Critical Implementation Detail**:
We use `AsyncStream.makeStream()` to create the stream and its continuation *before* the connection starts. This prevents a race condition where data received immediately upon connection could be lost if the stream wasn't fully initialized.

```swift
// PL2303Driver.swift
private let (stream, continuation) = AsyncStream<String>.makeStream()

driver.startReading { data in
    let str = String(decoding: data, as: UTF8.self) // Lossy decoding
    continuation.yield(str)
}
```

---

## 4. Transmission (`SerialConnection.swift`)

### Line Buffering
Raw serial data often arrives fragmented (e.g., "Hello" might arrive as "He" and "llo"). To present this cleanly in the UI, `SerialConnection` implements a **Line Buffer**.

1.  **Accumulation**: Incoming strings are appended to `currentLine`.
2.  **Detection**: We scan for newline characters (`\n`).
3.  **Extraction**: complete lines are extracted, trimmed, and moved to the persistent log.

### UI Presentation Logic
To avoid the user having to scroll constantly while monitoring a fast stream:
1.  **Storage**: Logs are stored in an array `logLines`.
2.  **Order**: New lines are appended to the end of the array.
3.  **Auto-Scroll**: The UI (`TerminalView`) uses `ScrollViewReader` to automatically scroll to the bottom (`proxy.scrollTo(lastID)`) whenever the line count changes.
