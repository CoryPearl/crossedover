import Foundation
import CrossedOverCore

@main struct Supervisor {
    static func main() async {
        do {
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--launch-worker" {
                try SupervisorEngine.runLaunchWorker(requestFile: URL(fileURLWithPath: CommandLine.arguments[2])); return
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 65_536 else { throw CrossedOverError.message("Supervisor request is too large.") }
            let request = try JSONDecoder().decode(SupervisorRequest.self, from: data)
            let reply = try await SupervisorEngine.execute(request)
            FileHandle.standardOutput.write(try JSONEncoder().encode(reply))
        } catch {
            let reply = SupervisorReply(success: false, message: error.localizedDescription)
            if let data = try? JSONEncoder().encode(reply) { FileHandle.standardOutput.write(data) }
            exit(1)
        }
    }
}
