import SwiftUI

struct ContentView: View {
    @State private var serialManager = SerialPortManager()
    @State private var selectedDevice: SerialDevice?
    
    var body: some View {
        NavigationSplitView {
            List(serialManager.availableDevices, selection: $selectedDevice) { device in
                // Row Content
                if let path = device.path {
                    VStack(alignment: .leading) {
                        Text(device.name).font(.headline)
                        Text(path).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(device) // explicitly tag if needed, but usually implicit. Putting it here is safe.
                } else {
                    // Raw USB Device (User-Space)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name).font(.headline)
                            Text("Ready (User-Space Driver)").font(.caption).foregroundStyle(.blue)
                            Text("Official Driver Missing").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "cpu").foregroundStyle(.blue)
                    }
                    .tag(device)
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                Button(action: { serialManager.refreshDevices() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } detail: {
            if let device = selectedDevice {
                 TerminalView(device: device)
            } else {
                Text("Select a device to connect")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
