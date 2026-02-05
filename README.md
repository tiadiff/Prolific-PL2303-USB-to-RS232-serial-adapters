# Prolific PL2303 USB-to-Serial Driver

A native, **Driverless** solution for connecting Prolific PL2303 USB-to-Serial adapters on modern macOS versions (Sequoia 15+).

## 🚀 The Problem

On macOS 15, the legacy kernel extensions (`.kext`) for Prolific PL2303 chips are deprecated or entirely blocked. <br>
Users often find that plugging in their device results in... nothing. <br><br>
No `/dev/cu.usbserial` appears, and official drivers fail to load.

## 🛠 The Solution

This repository contains **PL2303Term**, a Swift application that implements a custom **User-Space Driver**. <br><br>
Instead of relying on a kernel driver to create a virtual serial port, this app communicates directly with the USB device using `IOKit` and raw USB commands.

### Key Features

*   **Native User-Space Driver**: Bypass the need for Kernel Extensions.
*   **Direct USB Communication**: Reverse-engineered protocol implementation for PL2303HX and compatible chips.
*   **Built-in Terminal**: Send and receive data directly within the app.
*   **Custom Line Buffering**: Handles fragmented USB packets and displays data cleanly (Newest lines at bottom).
*   **Auto-Reconnect**: Seamlessly handles device plugging/unplugging.

## 📖 Technical Implementation

We have fully documented the reverse-engineering and implementation details of the driver.

👉 **[Read the Driver Implementation Docs](PL2303Term/PL2303_Driver_Docs.md)**

The driver uses a mixed-language approach:
*   **Objective-C Core**: For low-level `IOKit` pointer manipulation and USB control requests.
*   **Swift Layer**: For high-level concurrency (`AsyncStream`), data buffering, and UI.

## 📦 How to Build

1.  Clone the repository.
2.  Open the project folder.
3.  Run the build script:
    ```bash
    cd PL2303Term
    ./build.sh
    ```
4.  The application `PL2303Term.app` will be in the `build/Release` folder.

## 🔌 Supported Devices

*   **Vendor ID**: `0x067B` (Prolific Technology, Inc.)
*   **Product ID**: `0x2303` / `0x23C3` (Common PL2303 variants)

## (OPTIONAL) - Official drivers finally found:

* https://www.prolific.com.tw/en/portfolio-item/pl2303gt/ - (NOT TESTED)
* https://plugable.com/pages/prolific-drivers?srsltid=AfmBOoruWUZnZ7xaRd7toDLv2mZ8XvDf6I47LrPpQO6wtb7PQdzghEF3 - (NOT TESTED)
* https://www.startech.com/en-us/cards-adapters/icusb232v2#heading-driver-and-downloads - (NOT TESTED)
* http://support.dlink.com.au/Download/download.aspx?product=DGS-3630-52TC - (NOT TESTED)

## ⚖️ License

MIT License. Feel free to fork and improve!
