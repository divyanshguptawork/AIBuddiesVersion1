import SwiftUI
import AppKit

struct BuddyDock: View {
    let buddies: [BuddyModel] // This array now comes directly from ContentView, populated by BuddyModel.allBuddies
    @Binding var openBuddies: Set<String>
    @Binding var currentBuddyID: String?
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            buddyListScrollView
            expandCollapseButton
        }
        .padding(.trailing, 6)
        .frame(minWidth: 80)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(12)
        .shadow(radius: 6)
    }

    // MARK: - Private Helper Views for Body Refactoring

    private var buddyListScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: expanded ? 45 : -12) {
                ForEach(buddies, id: \.id) { buddy in
                    // Only show if not open OR if dock is expanded
                    if !openBuddies.contains(buddy.id) || expanded {
                        buddyAvatarButton(for: buddy)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(
            maxHeight: expanded ? CGFloat(min(buddies.count, 6)) * 85 : 150
        )
    }

    private func buddyAvatarButton(for buddy: BuddyModel) -> some View {
        Button(action: {
            handleBuddyClick(buddy)
        }) {
            // FIX: Use buddy.avatar directly, which should be "avatar1", "avatar2", etc.
            Image(buddy.avatar) // Corrected: Accessing 'avatar' property
                .resizable()
                .scaledToFit()
                .frame(width: expanded ? 70 : 50, height: expanded ? 70 : 50)
                .background(Color.clear)
                .cornerRadius(35)
                .overlay(
                    RoundedRectangle(cornerRadius: 35)
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: 3)
                .help(buddy.name)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var expandCollapseButton: some View {
        Button(action: {
            withAnimation { expanded.toggle() }
        }) {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .padding(6)
                .background(VisualEffectView(material: .toolTip, blendingMode: .withinWindow))
                .clipShape(Circle())
                .shadow(radius: 2)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Private Functions

    private func handleBuddyClick(_ buddy: BuddyModel) {
        print("Clicked: \(buddy.name)")
        if let currentID = currentBuddyID, currentID != buddy.id {
            let alert = NSAlert()
            alert.messageText = "Switch Buddy?"
            alert.informativeText = "Close \(currentID.capitalized) and open \(buddy.name)?"
            alert.addButton(withTitle: "Yes")
            alert.addButton(withTitle: "No")
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                BuddyWindowManager.shared.close(buddyID: currentID)
                BuddyWindowManager.shared.open(buddy: buddy)
                currentBuddyID = buddy.id
                openBuddies = [buddy.id]
            } else {
                BuddyWindowManager.shared.open(buddy: buddy)
                openBuddies.insert(buddy.id)
                currentBuddyID = buddy.id
            }
        } else {
            BuddyWindowManager.shared.open(buddy: buddy)
            openBuddies.insert(buddy.id)
            currentBuddyID = buddy.id
        }
    }
}

// Native macOS blur
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
