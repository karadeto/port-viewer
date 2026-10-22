import SwiftUI

@main
struct PortViewerApp: App {
    @State private var store = PortStore()

    var body: some Scene {
        MenuBarExtra {
            PortListView(store: store)
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.window)
    }
}
