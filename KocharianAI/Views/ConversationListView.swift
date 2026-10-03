import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var models: ModelManager
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var showSettings = false

    var body: some View {
        List(selection: $store.selectedID) {
            Section {
                ForEach(store.filtered) { conversation in
                    NavigationLink(value: conversation.id) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if conversation.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.accent)
                                }
                                Text(conversation.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            Text(conversation.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.delete(conversation.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { store.togglePin(conversation.id) } label: {
                            Label("Pin", systemImage: "pin")
                        }
                        .tint(Theme.accent)
                        Button {
                            renaming = conversation
                            renameText = conversation.title
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                }
            } header: {
                Text("Chats")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search chats")
        .navigationTitle("Kocharian AI")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings).environmentObject(models)
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil },
                                                   set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { store.rename(renaming.id, to: renameText) }
                renaming = nil
            }
        }
    }
}
