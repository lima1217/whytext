import Foundation
import WhyTextApp

@main
enum WhyTextStateMachineTests {
    static func main() async throws {
        try await StateMachineSelfTests.runAll()
        print("WhyText state-machine tests passed")
    }
}
