import Foundation

@MainActor
protocol NookDraftSaving: AnyObject {
    var hasUnsavedDraft: Bool { get }
    var errorMessage: String? { get }
    func retrySave() -> Bool
}

extension NookEditorBridge: NookDraftSaving {}

/// One gate is shared by note navigation, normal quit, and update relaunch.
/// The native draft remains mounted when serialization cannot complete.
@MainActor
final class NookEditingSession {
    private var draft: NookDraftSaving?
    var hasUnsavedDraft: Bool { draft?.hasUnsavedDraft == true }
    var errorMessage: String? { hasUnsavedDraft ? draft?.errorMessage : nil }

    func attach(_ draft: NookDraftSaving) { self.draft = draft }

    func prepareToLeave() -> Bool {
        guard let draft, draft.hasUnsavedDraft else { return true }
        return draft.retrySave() && !draft.hasUnsavedDraft
    }

    /// Deleting the note is already an explicit discard action.
    func discardDeletedNote() { draft = nil }
}
