import BackgroundTasks
import Observation
import SwiftUI
import UserNotifications

/// Somebody invites the learner to a battle or a party: a banner while the app is open, a notification otherwise.
/// The inbox is polled (there's no push service): every few seconds while the app is open, for half a minute after it
/// goes to the background, and whenever iOS grants a background refresh.
@MainActor
@Observable
final class Invites {
    static let shared = Invites()
    nonisolated static let taskId = "com.asbestboi.meitian.invites"
    nonisolated static let settingKey = "inviteNotifications"

    /// Accepted (banner or notification): the hub opens and joins it.
    var joining: InviteRef?
    /// In a battle: no banners.
    @ObservationIgnored var busy = false
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var shownRoom: String?
    private static let toldKey = "invitesTold"

    nonisolated static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// Looks for invitations nobody has told the learner about yet.
    func poll(foreground: Bool) async {
        let online = OnlineService.shared
        guard online.signedIn else { return }
        await online.refreshInbox()
        guard let inbox = online.inbox else { return }
        let open = inbox.challenges.map(\.room)
        // an invitation that's gone (answered, expired, taken back) takes its banner and notification along
        if let room = shownRoom, !open.contains(room) { hideBanner() }
        if foreground && busy { return }
        let told = UserDefaults.standard.stringArray(forKey: Self.toldKey) ?? []
        let gone = told.filter { !open.contains($0) }
        if !gone.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gone.map { "invite-\($0)" }) }
        let fresh = newInvites(inbox: inbox, told: told)
        UserDefaults.standard.set(Array((told.filter { open.contains($0) } + fresh.map(\.room)).suffix(50)), forKey: Self.toldKey)
        guard let newest = fresh.first else { return }
        if foreground {
            SFX.shared.play(.go)
            showBanner(newest)
        } else if Self.enabled {
            fresh.forEach(notify)
        }
    }

    private func notify(_ invite: OnlineChallenge) {
        let text = inviteText(invite: invite)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.userInfo = ["invite": invite.room]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "invite-\(invite.room)", content: content, trigger: nil))
    }

    /// Asks once, so invitations can be shown while the app is closed.
    func askPermission() async {
        guard Self.enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined { _ = await Reminders.allow() }
    }

    // MARK: while the app is closed

    func schedule() {
        guard Self.enabled, OnlineService.shared.signedIn else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The app just went to the background: iOS gives it about half a minute more.
    func lingerInBackground() {
        guard Self.enabled, OnlineService.shared.signedIn else { return }
        schedule()
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
        Task {
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(6))
                if UIApplication.shared.applicationState != .background { break }
                await poll(foreground: false)
            }
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
            id = .invalid
        }
    }

    // MARK: the banner (its own little window, so it also shows over lessons and stories)

    private func showBanner(_ invite: OnlineChallenge) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        hideBanner()
        shownRoom = invite.room
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        let top = scene.windows.first?.safeAreaInsets.top ?? 0
        w.frame = CGRect(x: 0, y: top, width: scene.coordinateSpace.bounds.width, height: 170)
        let host = UIHostingController(rootView: InviteBanner(invite: invite) { [weak self] accept in
            self?.hideBanner()
            if accept { self?.join(invite) }
        })
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        w.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
        let room = invite.room
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.shownRoom == room { self?.hideBanner() }   // it stays in the inbox
        }
    }

    private func hideBanner() {
        window?.isHidden = true
        window = nil
        shownRoom = nil
    }

    /// Closes whatever is open and joins.
    func join(_ invite: OnlineChallenge) {
        let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first { $0.windowLevel == .normal }?.rootViewController
        if let root, root.presentedViewController != nil {
            root.dismiss(animated: true) { self.joining = InviteRef(invite: invite) }
        } else {
            joining = InviteRef(invite: invite)
        }
    }

    /// A notification was tapped.
    func open(room: String) async {
        await OnlineService.shared.refreshInbox()
        if let invite = OnlineService.shared.inbox?.challenges.first(where: { $0.room == room }) { join(invite) }
    }
}

struct InviteRef: Identifiable {
    let invite: OnlineChallenge
    var id: String { invite.room }
}

/// Taps on notifications.
final class NotificationTaps: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTaps()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let room = response.notification.request.content.userInfo["invite"] as? String
        if let room { Task { @MainActor in await Invites.shared.open(room: room) } }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // the app shows its own banner for invitations
        completionHandler(notification.request.content.userInfo["invite"] == nil ? [.banner, .sound] : [])
    }
}

/// Drops in from the top, wherever the learner is.
struct InviteBanner: View {
    let invite: OnlineChallenge
    let answer: (Bool) -> Void

    var body: some View {
        let text = inviteText(invite: invite)
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                OnlineAvatar(profile: invite.from)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title).font(.rounded(.headline, weight: .heavy))
                    Text(text.body.components(separatedBy: ". Tap").first ?? text.body).font(.rounded(.footnote)).opacity(0.9)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                BigButton(title: invite.party.isEmpty ? "accept" : "join", gradient: Theme.jadeGradient) { answer(true) }
                BigButton(title: "no thanks") {
                    let room = invite.room
                    Task { try? await OnlineService.shared.decline(room); await OnlineService.shared.refreshInbox() }
                    answer(false)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Theme.pinkGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
