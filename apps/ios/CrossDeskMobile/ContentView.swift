import SwiftUI
import UIKit

enum MobileLayout {
    static let twoColumnBreakpoint: CGFloat = 900
    static let homeMaximumWidth: CGFloat = 1200
    static let readableMaximumWidth: CGFloat = 720
}

extension View {
    // Keep change callbacks available on iOS 16 without using the deprecated
    // overload on newer systems. Neither branch fires on initial appearance.
    @ViewBuilder
    func onValueChange<Value: Equatable>(of value: Value,
                                         perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    func readableContentWidth() -> some View {
        frame(maxWidth: MobileLayout.readableMaximumWidth)
            .frame(maxWidth: .infinity)
    }
}

enum HomeDestination: Hashable {
    case settings
    case announcements
    case announcement(AnnouncementSelection)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: RemoteSessionModel

    var body: some View {
        Group {
            if session.sessionVisible {
                RemoteSessionView(session: session)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    ConnectionHomeView(session: session)
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        // Keep inbox and detail in the same value-based stack.
                        // Mixing an isPresented inbox with a value-based detail
                        // can reinsert the inbox above the detail on updates.
                        .navigationDestination(for: HomeDestination.self) { destination in
                            switch destination {
                            case .settings:
                                ServerSettingsView(session: session)
                            case .announcements:
                                AnnouncementInboxView(session: session, inbox: session.announcements)
                            case .announcement(let selection):
                                AnnouncementDetailView(inbox: session.announcements, selection: selection)
                            }
                        }
                }
                .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.sessionVisible)
        .environmentObject(session.appUpdates)
        .preferredColorScheme(session.sessionVisible ? .dark : .light)
        .sheet(isPresented: Binding(
            get: { session.privacyNoticeVisible },
            set: { if !$0 { session.dismissPrivacyNotice() } }
        )) {
            PrivacyConsentView(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
        .alert(NSLocalizedString("连接提示", comment: ""), isPresented: Binding(
            get: { session.connectionFailureMessage != nil },
            set: { if !$0 { session.dismissConnectionFailure() } }
        )) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) { session.dismissConnectionFailure() }
        } message: {
            Text(session.connectionFailureMessage ?? "")
        }
        .onAppear {
            if !session.sessionVisible {
                AppOrientation.endSession()
            }
            if scenePhase == .active {
                session.applicationDidBecomeActive()
            }
        }
        .onValueChange(of: scenePhase) { phase in
            if phase == .active {
                session.applicationDidBecomeActive()
            } else if phase == .background {
                session.applicationDidEnterBackground()
            }
        }
    }
}

private struct KeyboardDismissTapView: UIViewRepresentable {
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        installRecognizer(for: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        installRecognizer(for: view, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    private func installRecognizer(for view: UIView, coordinator: Coordinator) {
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let window = view?.window else { return }
            coordinator?.install(in: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func install(in window: UIWindow) {
            guard self.window !== window || recognizer == nil else { return }
            uninstall()

            let recognizer = UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapOutsideInput))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.window = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer {
                window?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        @objc private func didTapOutsideInput() {
            onDismiss()
            window?.endEditing(true)
        }
    }
}

private struct ConnectionHomeView: View {
    @EnvironmentObject private var appUpdates: AppUpdateChecker
    @ObservedObject var session: RemoteSessionModel
    @FocusState private var remoteIDFocused: Bool
    @State private var passwordPromptVisible = false
    @State private var promptRemoteID = ""
    @State private var promptPassword = ""
    @State private var promptRememberPassword = false
    @State private var groupFilter: String?
    @State private var groupDevice: RecentConnection?

    private let connectionAccent = Color(red: 0.18, green: 0.48, blue: 0.86)

    private var trimmedRemoteID: String {
        session.remoteID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupedRemoteID: Binding<String> {
        Binding(
            get: { formatRemoteID(session.remoteID) },
            set: { value in
                session.remoteID = String(value.replacingOccurrences(of: " ", with: "").prefix(160))
            }
        )
    }

    private var signalIsConnected: Bool { session.signalConnected }
    private var signalHasError: Bool { session.signalHasError }

    private var signalTint: Color {
        if signalIsConnected { return .green }
        if signalHasError { return .red }
        return .orange
    }

    private var signalSymbol: String {
        if signalIsConnected { return "checkmark.circle.fill" }
        if signalHasError { return "exclamationmark.triangle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private func recentConnectionColumns(windowWidth: CGFloat) -> [GridItem] {
        if windowWidth >= 600 {
            return [GridItem(.adaptive(minimum: 180), spacing: 12, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: 12, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top)
        ]
    }

    private var recentGroups: [String] {
        Set(session.recentConnections.flatMap(\.groups)).sorted()
    }

    private var orderedRecentConnections: [RecentConnection] {
        session.recentConnections.enumerated()
            .filter { entry in
                guard let groupFilter else { return true }
                return groupFilter.isEmpty ? entry.element.groups.isEmpty : entry.element.groups.contains(groupFilter)
            }
            .sorted { lhs, rhs in
                let lhsOnline = session.isRecentConnectionOnline(lhs.element)
                let rhsOnline = session.isRecentConnectionOnline(rhs.element)
                if lhsOnline != rhsOnline { return lhsOnline }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var body: some View {
        ZStack {
            CDCanvasBackground()

            GeometryReader { proxy in
                let isWide = proxy.size.width >= MobileLayout.twoColumnBreakpoint
                // AnyLayout keeps the fields, focus and scroll view alive when
                // rotation or iPad multitasking crosses the layout breakpoint.
                let layout = isWide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    : AnyLayout(VStackLayout(spacing: 20))

                ScrollView(.vertical) {
                    VStack(spacing: 16) {
                        homeHeader

                        layout {
                            remoteConnectionPanel
                                .frame(width: isWide ? 360 : nil)
                            recentConnectionsPanel(windowWidth: proxy.size.width)
                                .frame(maxHeight: .infinity)
                        }
                        // Short multitasking windows and the onscreen keyboard
                        // must not squeeze the recent list below a usable height.
                        .frame(height: max(isWide ? 260 : 420, proxy.size.height - 136),
                               alignment: .top)
                    }
                    .frame(maxWidth: MobileLayout.homeMaximumWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if session.isConnecting {
                connectionProgressOverlay
            }

        }
        .toolbar {
            if #available(iOS 26.0, *) {
                navigationToolbar.sharedBackgroundVisibility(.hidden)
            } else {
                navigationToolbar
            }
        }
        .background {
            KeyboardDismissTapView {
                remoteIDFocused = false
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $passwordPromptVisible) {
            PasswordPromptView(remoteID: promptRemoteID,
                               password: $promptPassword,
                               rememberPassword: $promptRememberPassword) {
                guard passwordPromptVisible, session.canStartConnection else { return }
                passwordPromptVisible = false
                session.remoteID = promptRemoteID
                session.connect(password: promptPassword,
                                rememberPassword: promptRememberPassword)
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $groupDevice) { device in
            RecentGroupEditor(device: device, groups: recentGroups) { groups in
                session.editRecentConnection(device.id, groups: groups)
            }
            .presentationDetents([.medium, .large])
        }
        .onValueChange(of: recentGroups) { groups in
            if let groupFilter, !groupFilter.isEmpty, !groups.contains(groupFilter) {
                self.groupFilter = nil
            }
        }
        .alert(NSLocalizedString("设备离线", comment: ""), isPresented: Binding(
            get: { session.deviceOfflineAlertVisible },
            set: { visible in
                if !visible { session.dismissDeviceOfflineAlert() }
            }
        )) {
            Button(NSLocalizedString("确定", comment: "")) {
                session.dismissDeviceOfflineAlert()
            }
        }
        .onDisappear { remoteIDFocused = false }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "CrossDesk")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(CDTheme.brandGradient)
                Text(NSLocalizedString("远程桌面", comment: ""))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !session.recentConnections.isEmpty {
                CDPill(text: String(format: NSLocalizedString("%1$@ 台设备", comment: ""),
                                    String(session.recentConnections.count)),
                       systemImage: "desktopcomputer",
                       tint: CDTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if session.hasNetworkConsent {
                signalStatusBadge
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Button {
                    remoteIDFocused = false
                    session.showPrivacyNotice()
                } label: {
                    signalStatusBadge
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("打开隐私政策", comment: ""))
            }
        }
        ToolbarItem(placement: announcementPlacement) {
            NavigationLink(value: HomeDestination.announcements) {
                AnnouncementBadge(inbox: session.announcements)
            }
            .foregroundStyle(.primary)
            .disabled(session.isConnecting)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            NavigationLink(value: HomeDestination.settings) {
                CDIconTile(systemImage: "gearshape", showsDot: appUpdates.updateAvailable)
            }
            .disabled(session.isConnecting)
            .accessibilityLabel(appUpdates.updateAvailable ? NSLocalizedString("设置，有新版本", comment: "") : NSLocalizedString("设置", comment: ""))
        }
    }

    private var announcementPlacement: ToolbarItemPlacement {
        if #available(iOS 27.0, *) { return .topBarPinnedTrailing }
        return .navigationBarTrailing
    }

    private var signalStatusBadge: some View {
        HStack(spacing: 6) {
            if session.hasNetworkConsent {
                Image(systemName: signalSymbol)
                    .font(.caption.weight(.bold))
            }
            Text(session.signalStatus)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(signalTint)
        .padding(.horizontal, 11)
        // Leave room for both toolbar actions even when the status is an error.
        .frame(maxWidth: 160, minHeight: 34, maxHeight: 34, alignment: .leading)
        .background(signalTint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(signalTint.opacity(0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    private var remoteConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(remoteIDFocused ? CDTheme.accent : Color.secondary)
                    TextField(NSLocalizedString("设备 ID 或 IP 地址", comment: ""), text: groupedRemoteID)
                        .keyboardType(.asciiCapable)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .focused($remoteIDFocused)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .cdInset(radius: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(remoteIDFocused ? CDTheme.accent : Color.clear,
                                      lineWidth: 1.6)
                }
                .shadow(color: remoteIDFocused ? CDTheme.accent.opacity(0.14) : .clear,
                        radius: 10, x: 0, y: 3)

                Button {
                    presentPasswordPrompt(for: trimmedRemoteID)
                } label: {
                    Text(NSLocalizedString("连接", comment: ""))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(CDPrimaryButtonStyle(height: 54, radius: 16))
                .frame(width: 104)
                .disabled(trimmedRemoteID.isEmpty || session.isConnecting)
                .accessibilityLabel(NSLocalizedString("连接", comment: ""))
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(NSLocalizedString("请输入设备 ID 或有效的 IP 地址", comment: ""))
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.tertiary)
        }
        .cdCard(padding: 16)
    }

    private var recentGroupPicker: some View {
        let all = NSLocalizedString("全部设备", comment: "")
        let ungrouped = NSLocalizedString("未分组", comment: "")
        let selected = groupFilter.map { $0.isEmpty ? ungrouped : $0 } ?? all
        return Menu {
            Picker(NSLocalizedString("分组", comment: ""), selection: $groupFilter) {
                Text(all).tag(nil as String?)
                Text(ungrouped).tag(Optional(""))
                ForEach(recentGroups, id: \.self) { group in
                    Text(verbatim: group).tag(Optional(group))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: selected).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(NSLocalizedString("分组", comment: ""))
        .accessibilityValue(Text(verbatim: selected))
    }

    @ViewBuilder
    private func recentConnectionsPanel(windowWidth: CGFloat) -> some View {
        let connections = orderedRecentConnections
        let countText = String(format: NSLocalizedString("%1$@ 台设备", comment: ""),
                               String(connections.count))
        VStack(alignment: .leading, spacing: 14) {
            if session.recentConnections.isEmpty {
                CDSectionTitle(title: NSLocalizedString("最近连接", comment: ""))
            } else {
                ViewThatFits(in: .horizontal) {
                    CDSectionTitle(title: NSLocalizedString("最近连接", comment: ""),
                                   subtitle: countText) {
                        recentGroupPicker
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        CDSectionTitle(title: NSLocalizedString("最近连接", comment: ""),
                                       subtitle: countText)
                        recentGroupPicker
                    }
                }
            }

            if session.recentConnections.isEmpty {
                CDEmptyState(systemImage: "clock.arrow.circlepath",
                             title: NSLocalizedString("还没有连接记录", comment: ""),
                             message: NSLocalizedString("成功连接后，这里会显示远端桌面的缩略图。", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if connections.isEmpty {
                CDEmptyState(systemImage: "folder",
                             title: NSLocalizedString("该分组暂无近期连接", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: recentConnectionColumns(windowWidth: windowWidth), spacing: 12) {
                        ForEach(connections) { connection in
                            RecentConnectionCard(
                                connection: connection,
                                thumbnail: session.thumbnailImage(for: connection),
                                online: session.isRecentConnectionOnline(connection),
                                connect: {
                                    connectRecent(connection)
                                },
                                rename: { session.editRecentConnection(connection.id, alias: $0) },
                                editGroups: { groupDevice = connection },
                                delete: {
                                    session.removeRecentConnection(connection)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cdCard(padding: 16)
    }

    private var connectionProgressOverlay: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CDTheme.accent.opacity(0.12))
                            .frame(width: 58, height: 58)
                        Image(systemName: "display")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(CDTheme.brandGradient)
                    }
                    .accessibilityHidden(true)

                    ProgressView()
                        .controlSize(.large)
                        .tint(connectionAccent)

                    VStack(spacing: 6) {
                        Text(NSLocalizedString("正在连接", comment: ""))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(session.connectionStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(minHeight: 36)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider()

                Button(role: .cancel, action: session.disconnect) {
                    Text(NSLocalizedString("取消连接", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 292)
            .background(Color.white,
                        in: RoundedRectangle(cornerRadius: 24,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(.separator).opacity(0.24), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func presentPasswordPrompt(for identifier: String) {
        guard !passwordPromptVisible, session.canStartConnection else { return }
        guard session.hasNetworkConsent else {
            remoteIDFocused = false
            session.showPrivacyNotice()
            return
        }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remoteIDFocused = true
            return
        }
        remoteIDFocused = false
        guard let target = session.connectionTarget(trimmed) else { return }
        promptRemoteID = target
        promptPassword = session.savedPassword(for: target)
        promptRememberPassword = session.remembersPassword(for: target)
        passwordPromptVisible = true
    }

    private func formatRemoteID(_ value: String) -> String {
        guard value.count <= 9, value.allSatisfy({ $0.isNumber }) else { return value }
        let digits = Array(value)
        return stride(from: 0, to: digits.count, by: 3)
            .map { start in
                String(digits[start..<min(start + 3, digits.count)])
            }
            .joined(separator: " ")
    }

    private func connectRecent(_ connection: RecentConnection) {
        guard !passwordPromptVisible, session.canStartConnection else { return }
        session.remoteID = connection.remoteID
        remoteIDFocused = false

        if connection.remembersPassword,
           let savedPassword = session.savedCredential(for: connection.remoteID) {
            session.connect(password: savedPassword, rememberPassword: true)
        } else {
            presentPasswordPrompt(for: connection.remoteID)
        }
    }
}

private struct RecentConnectionCard: View {
    let connection: RecentConnection
    let thumbnail: UIImage?
    let online: Bool
    let connect: () -> Void
    let rename: (String) -> Void
    let editGroups: () -> Void
    let delete: () -> Void
    @State private var renaming = false
    @State private var nameDraft = ""

    private var platformGradient: LinearGradient {
        LinearGradient(colors: CDTheme.platformGradient(for: connection.platform),
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    private var isDirectAddress: Bool { connection.remoteID.contains(":") }

    private var statusText: String {
        if isDirectAddress { return "IP" }
        return online ? NSLocalizedString("在线", comment: "") : NSLocalizedString("离线", comment: "")
    }

    var body: some View {
        Button(action: connect) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            platformGradient
                            Text(connection.platform.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(.white)
                                .padding(10)
                                .accessibilityLabel(String(format: NSLocalizedString("被控端平台：%1$@", comment: ""), String(describing: connection.platform.displayName)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipped()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(online ? CDTheme.success : Color.white.opacity(0.7))
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.42), in: Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !connection.groups.isEmpty {
                        Text(connection.groups.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        Text(isDirectAddress ? connection.remoteID : "ID \(connection.remoteID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if connection.remembersPassword {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(NSLocalizedString("已保存密码", comment: ""))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .background(CDTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CDTheme.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .contextMenu { actions }
        .overlay(alignment: .topTrailing) {
            Menu { actions } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("更多操作", comment: ""))
        }
        .alert(NSLocalizedString("修改名称", comment: ""), isPresented: $renaming) {
            TextField(connection.hostName, text: $nameDraft)
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("保存", comment: "")) { rename(nameDraft) }
        } message: {
            Text(isDirectAddress ? connection.remoteID : "ID \(connection.remoteID)")
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: connect) { Label(NSLocalizedString("连接", comment: ""), systemImage: "arrow.right") }
        Button {
            nameDraft = connection.displayName
            renaming = true
        } label: { Label(NSLocalizedString("修改名称", comment: ""), systemImage: "pencil") }
        Button(action: editGroups) { Label(NSLocalizedString("修改分组", comment: ""), systemImage: "folder") }
        Button(role: .destructive, action: delete) {
            Label(NSLocalizedString("删除记录", comment: ""), systemImage: "trash")
        }
    }
}

private struct RecentGroupEditor: View {
    let device: RecentConnection
    let groups: [String]
    let save: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var newGroup = ""

    init(device: RecentConnection, groups: [String], save: @escaping ([String]) -> Void) {
        self.device = device
        self.groups = groups
        self.save = save
        _selected = State(initialValue: Set(device.groups))
    }

    private var trimmedGroup: String { newGroup.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([""] + groups, id: \.self) { group in
                        let checked = group.isEmpty ? selected.isEmpty && trimmedGroup.isEmpty : selected.contains(group)
                        Button {
                            if group.isEmpty { selected.removeAll(); newGroup = "" }
                            else if selected.contains(group) { selected.remove(group) }
                            else { selected.insert(group) }
                        } label: {
                            HStack {
                                Text(group.isEmpty ? NSLocalizedString("未分组", comment: "") : group)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if checked { Image(systemName: "checkmark") }
                            }
                        }
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                    TextField(NSLocalizedString("新建分组（可选）", comment: ""), text: $newGroup)
                } header: {
                    Text("\(device.displayName) · ID \(device.id)").textCase(nil)
                }
            }
            .navigationTitle(NSLocalizedString("修改分组", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        if !trimmedGroup.isEmpty { selected.insert(trimmedGroup) }
                        save(Array(selected))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PasswordPromptView: View {
    let remoteID: String
    @Binding var password: String
    @Binding var rememberPassword: Bool
    let connect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var passwordFocused: Bool
    @State private var passwordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("连接远程桌面", comment: ""))
                        .font(.title2.bold())
                    Text(remoteID.contains(":") ? remoteID : String(format: NSLocalizedString("对端 ID  %1$@", comment: ""), remoteID))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(NSLocalizedString("关闭", comment: ""))
            }

            HStack(spacing: 10) {
                Group {
                    if passwordVisible {
                        TextField(NSLocalizedString(remoteID.contains(":") ? "IP 直连密码" : "访问密码", comment: ""), text: $password)
                    } else {
                        SecureField(NSLocalizedString(remoteID.contains(":") ? "IP 直连密码" : "访问密码", comment: ""), text: $password)
                    }
                }
                .keyboardType(.asciiCapable)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($passwordFocused)

                Button {
                    passwordVisible.toggle()
                } label: {
                    Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(passwordVisible ? NSLocalizedString("隐藏密码", comment: "") : NSLocalizedString("显示密码", comment: ""))
            }
            .padding(.horizontal, 13)
            .frame(height: 50)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
            }

            Toggle(isOn: $rememberPassword) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("保存密码", comment: ""))
                        .font(.subheadline.weight(.semibold))
                    Text(NSLocalizedString("密码将安全保存在本机 Keychain 中", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: connect) {
                Text(NSLocalizedString("连接", comment: ""))
            }
            .disabled(remoteID.contains(":") && password.range(of: "^[A-Za-z0-9]{6}$", options: .regularExpression) == nil)
            .buttonStyle(CDPrimaryButtonStyle(height: 48, radius: 14))
        }
        .padding(22)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                passwordFocused = true
            }
        }
    }
}

private struct DevicePairingView: View {
    let deviceID: String
    @State private var info: [String: String]?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text(NSLocalizedString("将配对信息添加到被控端的可信设备列表，并核对指纹。", comment: ""))
                if let info, let fingerprint = info["fingerprint"], let pairing = info["pairing"] {
                    Text(fingerprint.enumerated().map { index, character in
                        (index > 0 && index % 4 == 0 ? " " : "") + String(character)
                    }.joined()).font(.footnote.monospaced()).textSelection(.enabled)
                    Button(NSLocalizedString("复制配对信息", comment: "")) {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": pairing]], options: [.localOnly: true])
                        copied = true
                    }
                    if copied { Text(NSLocalizedString("配对信息已复制。", comment: "")).foregroundStyle(.secondary) }
                } else {
                    Text(NSLocalizedString("安全存储不可用，请解锁设备后重试", comment: "")).foregroundStyle(.orange)
                    Button(NSLocalizedString("重试", comment: "")) { load() }
                }
            }
        }
        .navigationTitle(NSLocalizedString("本机配对信息", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }
    private func load() { info = CrossDeskRTCBridge.deviceTrustInfo(forDeviceID: deviceID); copied = false }
}

private struct ServerSettingsView: View {
    @EnvironmentObject private var appUpdates: AppUpdateChecker
    @ObservedObject var session: RemoteSessionModel
    @State private var serverConfigurationExpanded = false
    @State private var usesCustomServer: Bool
    @State private var customServerHost: String
    @State private var customServerPort: String
    @State private var serverConfigurationError: String?
    @FocusState private var focusedServerField: ServerField?

    private enum ServerField: Hashable {
        case host, port
    }

    init(session: RemoteSessionModel) {
        self.session = session
        let server = session.customServer
        _usesCustomServer = State(initialValue: server != nil)
        _customServerHost = State(initialValue: server?.host ?? "")
        _customServerPort = State(initialValue: server.map { String($0.signalPort) } ?? "")
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("鼠标控制", comment: "")) {
                Picker(NSLocalizedString("控制模式", comment: ""), selection: $session.mouseControlMode) {
                    ForEach(MouseControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(NSLocalizedString("画面偏好", comment: "")) {
                Picker(NSLocalizedString("偏好模式", comment: ""), selection: $session.videoAdaptationPolicy) {
                    ForEach(VideoAdaptationPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(NSLocalizedString("连接建立后锁定横屏", comment: ""), isOn: $session.autoLandscape)
            } header: {
                Text(NSLocalizedString("屏幕方向", comment: ""))
            } footer: {
                Text(NSLocalizedString("默认关闭。开启后，iPhone 连接时进入并保持横屏；关闭时跟随设备方向。iPad 不受影响。", comment: ""))
            }
            Section {
                DisclosureGroup(isExpanded: $serverConfigurationExpanded) {
                    Toggle(NSLocalizedString("使用自定义服务器", comment: ""), isOn: $usesCustomServer)
                    if usesCustomServer {
                        LabeledContent(NSLocalizedString("地址", comment: "")) {
                            TextField(NSLocalizedString("填写服务器地址", comment: ""), text: $customServerHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedServerField, equals: .host)
                                .submitLabel(.next)
                                .onSubmit { focusedServerField = .port }
                                .accessibilityLabel(NSLocalizedString("服务器地址", comment: ""))
                        }
                        LabeledContent(NSLocalizedString("端口", comment: "")) {
                            TextField(NSLocalizedString("填写端口", comment: ""), text: $customServerPort)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedServerField, equals: .port)
                                .accessibilityLabel(NSLocalizedString("服务器端口", comment: ""))
                        }
                    }
                } label: {
                    HStack {
                        Text(NSLocalizedString("服务器", comment: ""))
                        Spacer()
                        Text(usesCustomServer ? NSLocalizedString("自定义", comment: "") : NSLocalizedString("默认", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if let serverConfigurationError {
                    Text(serverConfigurationError)
                        .foregroundStyle(.red)
                }
                if let warning = session.identityStorageWarning {
                    Text(warning)
                        .foregroundStyle(.orange)
                }
                Text(!session.hasNetworkConsent ? NSLocalizedString("完成隐私授权后登记本机身份", comment: "") : session.localIdentity.isEmpty
                     ? NSLocalizedString("正在获取本机 ID…", comment: "")
                     : String(format: NSLocalizedString("本机 ID  %1$@", comment: ""), String(describing: session.localIdentity)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                    .textSelection(.enabled)
            }
            PrivacySettingsSection(session: session)
            Section {
                NavigationLink(NSLocalizedString("本机配对信息", comment: "")) {
                    DevicePairingView(deviceID: session.localIdentity)
                }
            }
            Section {
                NavigationLink {
                    ThirdPartyLicensesView(session: session)
                } label: {
                    HStack {
                        Text(NSLocalizedString("关于", comment: ""))
                        Spacer()
                        if appUpdates.updateAvailable {
                            Text(NSLocalizedString("新版本", comment: "")).foregroundStyle(.secondary)
                            UpdateDot()
                        }
                    }
                }
                .accessibilityLabel(appUpdates.updateAvailable ? NSLocalizedString("关于，有新版本", comment: "") : NSLocalizedString("关于", comment: ""))
            }
        }
        .readableContentWidth()
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(NSLocalizedString("设置", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .background {
            KeyboardDismissTapView {
                focusedServerField = nil
            }
            .allowsHitTesting(false)
        }
        .onValueChange(of: serverConfigurationExpanded) { expanded in
            if !expanded {
                focusedServerField = nil
                validateAndApplyServerConfiguration()
            }
        }
        .onValueChange(of: usesCustomServer) { isCustom in
            if !isCustom { useDefaultServer() }
        }
        .onValueChange(of: focusedServerField) { field in
            if field == nil { validateAndApplyServerConfiguration() }
        }
        .onDisappear {
            // Native back navigation can remove the view before focus updates.
            focusedServerField = nil
            validateAndApplyServerConfiguration()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(NSLocalizedString("完成", comment: "")) {
                    focusedServerField = nil
                }
            }
        }
    }

    private func useDefaultServer() {
        serverConfigurationError = nil
        focusedServerField = nil
        customServerHost = ""
        customServerPort = ""
        session.setCustomServer(nil)
    }

    private func validateAndApplyServerConfiguration() {
        guard usesCustomServer else { return }
        let host = customServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = customServerPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            serverConfigurationError = NSLocalizedString("请输入服务器地址，或关闭“使用自定义服务器”。", comment: "")
            return
        }
        guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
            serverConfigurationError = NSLocalizedString("请输入 1–65535 范围内的端口，或关闭“使用自定义服务器”。", comment: "")
            return
        }
        serverConfigurationError = nil
        customServerHost = host
        customServerPort = String(portNumber)
        session.setCustomServer(SignalServerConfiguration(host: host, signalPort: portNumber))
    }
}
