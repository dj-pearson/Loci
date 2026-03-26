import AppIntents
import Foundation

struct OpenLocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Locus"
    static var description: IntentDescription = "Opens a specific locus in the Loci app."
    static var openAppWhenRun = true

    @Parameter(title: "Locus ID")
    var locusId: String

    init() {
        self.locusId = ""
    }

    init(locusId: UUID) {
        self.locusId = locusId.uuidString
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
