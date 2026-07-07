import Foundation
import Combine

class DownloaderManager: ObservableObject {
    static let shared = DownloaderManager()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var logs: String = ""
    
    private init() {}
    
    func downloadAudio(from urlString: String, destinationFolder: URL, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        logs = "Starting download from \(urlString)...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            
            // Assume am-dl is in /usr/local/bin or accessible via PATH
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/am-dl")
            process.arguments = [urlString, "--output", destinationFolder.path]
            process.standardOutput = pipe
            process.standardError = pipe
            
            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.logs += output
                        // Basic progress parsing (assuming am-dl outputs e.g. "[download] 45.3%")
                        if let range = output.range(of: "\\[download\\]\\s+([0-9.]+)", options: .regularExpression),
                           let percentageStr = output[range].components(separatedBy: .whitespaces).last,
                           let percentage = Double(percentageStr) {
                            self.downloadProgress = percentage / 100.0
                        }
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                    self.logs += "Download finished with code \(process.terminationStatus)\n"
                    completion(process.terminationStatus == 0)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.logs += "Failed to start process: \(error.localizedDescription)\n"
                    completion(false)
                }
            }
        }
    }
}
