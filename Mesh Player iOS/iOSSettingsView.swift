import SwiftUI

struct iOSSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @AppStorage("sync_icloud_enabled") private var syncICloud = true
    @AppStorage("sync_local_enabled") private var syncLocal = true
    @AppStorage("playback_hq_cellular") private var hqCellular = false
    @AppStorage("eq_mode") private var selectedEQ = "Flat (Default Lossless)"
    
    let eqModes = ["Flat (Default Lossless)", "Bass Booster (Sub-harmonic)", "Acoustic Live Concert Hall", "Classical (Symphonic Arc)", "Vocal Booster (Custom Lyrics Focus)", "Electronic Spectrum"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text("Peter Luedtke").foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Sync Settings")) {
                    Toggle("iCloud Sync", isOn: $syncICloud)
                    Toggle("Local Network Sync", isOn: $syncLocal)
                }
                
                Section(header: Text("Playback")) {
                    Toggle("High Quality on Cellular", isOn: $hqCellular)
                    Picker("Equalizer", selection: $selectedEQ) {
                        ForEach(eqModes, id: \.self) { mode in
                            Text(mode).tag(mode)
                        }
                    }
                }
                
                Section(header: Text("About Mesh Player")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
