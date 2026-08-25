import Foundation
import Darwin

setbuf(stdout, nil)
setbuf(stderr, nil)

let appServer = CodexAppServerClient()
do {
    if CommandLine.arguments.contains("--probe") {
        appServer.onReady = {
            appServer.probeLoadedThreads { exit(EXIT_SUCCESS) }
        }
        try appServer.start()
        RunLoop.main.run()
    }

    try appServer.start()
    let central = BLECentral(appServer: appServer)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    let shutdown = {
        appServer.stop()
        exit(EXIT_SUCCESS)
    }
    interruptSource.setEventHandler(handler: shutdown)
    terminateSource.setEventHandler(handler: shutdown)
    interruptSource.resume()
    terminateSource.resume()
    withExtendedLifetime(central) {
        RunLoop.main.run()
    }
} catch {
    fputs("CodexBridge: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
