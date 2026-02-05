import SwiftUI

struct TerminalView: View {
    let device: SerialDevice
    @State private var connection = SerialConnection()
    @State private var input = ""
    @State private var baudRate: BaudRate = .b9600
    
    var body: some View {
        VStack {
            // Header / Controls
            HStack {
                Picker("Baud Rate", selection: $baudRate) {
                    Text("9600").tag(BaudRate.b9600)
                    Text("19200").tag(BaudRate.b19200)
                    Text("38400").tag(BaudRate.b38400)
                    Text("57600").tag(BaudRate.b57600)
                    Text("115200").tag(BaudRate.b115200)
                }
                .disabled(connection.isConnected)
                
                if connection.isConnected {
                    Button("Disconnect", role: .destructive) {
                        connection.disconnect()
                    }
                } else {
                    Button("Connect") {
                        connection.connect(device: device, baudRate: baudRate)
                    }
                }
                
                Button("Clear") {
                    connection.clearLogs()
                }
                .disabled(connection.logLines.isEmpty && connection.currentLine.isEmpty)
            }
            .padding()
            
            Divider()
            
            // Terminal Output
            // Terminal Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(connection.logLines) { line in
                            Text(line.text)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        
                        if !connection.currentLine.isEmpty {
                            Text(connection.currentLine)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.blue) // Highlight active line
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("currentLine")
                        }
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .padding()
                .onChange(of: connection.logLines.count) { _ in
                    if let last = connection.logLines.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: connection.currentLine) { _ in
                     if !connection.currentLine.isEmpty {
                         withAnimation {
                             proxy.scrollTo("currentLine", anchor: .bottom)
                         }
                     }
                }
            }
            
            if let error = connection.error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .padding(.bottom)
            }
            
            // Input
            HStack {
                TextField("Send data...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        send()
                    }
                    .disabled(!connection.isConnected)
                
                Button("Send") {
                    send()
                }
                .disabled(!connection.isConnected || input.isEmpty)
            }
            .padding()
        }
        .navigationTitle(device.name)
        .onDisappear {
            // Auto disconnect when leaving the view
            if connection.isConnected {
                connection.disconnect()
            }
        }
    }
    
    private func send() {
        guard !input.isEmpty else { return }
        // Determine line ending - for now just raw or \n?
        // Let's append \r\n which is common for serial
        connection.send(text: input + "\r\n")
        input = ""
    }
}
