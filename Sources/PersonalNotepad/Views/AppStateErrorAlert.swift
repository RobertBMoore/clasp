import SwiftUI

private struct AppStateErrorAlertModifier: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        content.alert("Clasp Couldn’t Complete That", isPresented: Binding(
            get: { appState.presentedError != nil },
            set: { if !$0 { appState.presentedError = nil } }
        )) {
            Button("OK") { appState.presentedError = nil }
        } message: {
            Text(appState.presentedError ?? "An unknown error occurred.")
        }
    }
}

extension View {
    func appStateErrorAlert(_ appState: AppState) -> some View {
        modifier(AppStateErrorAlertModifier(appState: appState))
    }
}
