import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView()
        } detail: {
            NavigationStack {
                ChatView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
    }
}
