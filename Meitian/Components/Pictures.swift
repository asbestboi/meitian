import PhotosUI
import SwiftUI

/// A player's profile picture, or their initials on a colour of their own. `path` is the server's, "" for none.
struct PictureView: View {
    let id: String
    let name: String
    let path: String
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: avatarColor(playerId: id)))
            Text(initials(name: name))
                .font(.system(size: size * 0.42, weight: .heavy))
                .minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(.white)
            if !path.isEmpty, let url = URL(string: OnlineService.currentBase() + path) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)'s picture")
    }
}

struct OnlineAvatar: View {
    let profile: OnlineProfile?
    var size: CGFloat = 46

    var body: some View {
        PictureView(id: profile?.id ?? "", name: profile?.nickname ?? "", path: profile?.avatar ?? "", size: size)
    }
}

/// The learner's own picture.
struct MyPicture: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    var size: CGFloat

    var body: some View {
        let me = OnlineService.shared.profile
        PictureView(id: me?.id ?? arena.playerId,
                    name: store.profile.name.isEmpty ? (me?.nickname ?? "Learner") : store.profile.name,
                    path: me?.avatar ?? "", size: size)
    }
}

/// Picks and uploads a profile picture (creating the online profile from the learner's name if needed).
struct PictureUpload<Label: View>: View {
    /// Nickname for a new online profile.
    let name: String
    @Binding var note: String?
    @Binding var busy: Bool
    @ViewBuilder var label: Label
    @State private var photo: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $photo, matching: .images) { label }
            .buttonStyle(PressableStyle())
            .disabled(busy)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                busy = true
                Task { @MainActor in
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            note = "Couldn't read that picture."
                            busy = false
                            return
                        }
                        try await OnlineService.shared.ensureAccount(name: name)
                        try await OnlineService.shared.uploadAvatar(image)
                        note = "Looking good ✦"
                    } catch {
                        note = OnlineService.describe(error)
                    }
                    busy = false
                    photo = nil
                }
            }
    }
}
