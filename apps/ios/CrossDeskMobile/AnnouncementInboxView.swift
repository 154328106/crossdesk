import SwiftUI

struct AnnouncementBadge: View {
    @ObservedObject var inbox: AnnouncementInbox

    private var badgeText: String? {
        guard inbox.state.unread > 0 else { return nil }
        return inbox.state.unread > 99 ? "99+" : "\(inbox.state.unread)"
    }

    var body: some View {
        CDIconTile(systemImage: inbox.state.unread > 0 ? "envelope.badge.fill" : "envelope",
                   badgeText: badgeText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NSLocalizedString("通知公告", comment: ""))
            .accessibilityValue(inbox.state.unread > 0
                ? String(format: NSLocalizedString("%1$@ 条未读", comment: ""), String(describing: inbox.state.unread))
                : NSLocalizedString("无未读公告", comment: ""))
    }
}

struct AnnouncementSelection: Hashable {
    let id: Int64
    let revision: Int64
}

private enum AnnouncementDate {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Today shows only the time; older items show a locale-aware date.
    static func string(_ item: Announcement) -> String {
        if Calendar.current.isDateInToday(item.date) {
            return timeFormatter.string(from: item.date)
        }
        return dateFormatter.string(from: item.date)
    }
}

/// Inbox history. Reading state and dismissal are local to this device, so the
/// header actions work without a live connection.
struct AnnouncementInboxView: View {
    @ObservedObject var session: RemoteSessionModel
    @ObservedObject var inbox: AnnouncementInbox
    @State private var pendingDelete: Announcement?
    @State private var confirmClearAll = false

    private var state: AnnouncementSnapshot { inbox.state }

    private var canMarkAllRead: Bool { state.unread > 0 }
    private var canClearAll: Bool { !state.items.isEmpty || state.total > 0 }

    var body: some View {
        ZStack {
            CDCanvasBackground()

            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    summaryCard
                    banners
                    content
                }
                .padding(.horizontal, CDTheme.gutter)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .readableContentWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                session.refreshAnnouncements()
                while inbox.state.loading && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        .navigationTitle(NSLocalizedString("通知公告", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        session.refreshAnnouncements()
                    } label: {
                        Label(NSLocalizedString("刷新公告", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .disabled(state.loading || !session.announcementsConnected)

                    Button {
                        inbox.markAllRead()
                    } label: {
                        Label(NSLocalizedString("全部已读", comment: ""), systemImage: "checkmark.circle")
                    }
                    .disabled(!canMarkAllRead)

                    Divider()

                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label(NSLocalizedString("清除全部", comment: ""), systemImage: "trash")
                    }
                    .disabled(!canClearAll)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(NSLocalizedString("更多操作", comment: ""))
            }
        }
        .onAppear { session.refreshAnnouncements() }
        .alert(NSLocalizedString("删除公告", comment: ""), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { pendingDelete = nil }
            Button(NSLocalizedString("删除", comment: ""), role: .destructive) {
                if let item = pendingDelete { inbox.dismiss(item) }
                pendingDelete = nil
            }
        } message: {
            Text(NSLocalizedString("删除这条公告？", comment: ""))
        }
        .alert(NSLocalizedString("清除全部公告？", comment: ""), isPresented: $confirmClearAll) {
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("清除", comment: ""), role: .destructive) { inbox.dismissAll() }
        } message: {
            Text(NSLocalizedString("将清除本机保存的公告记录，服务端不受影响，之后仍会收到新公告。", comment: ""))
        }
    }

    // MARK: Header

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                CDMetric(value: String(describing: state.unread),
                         label: NSLocalizedString("未读", comment: ""),
                         tint: state.unread > 0 ? CDTheme.unread : .secondary)
                Divider().frame(height: 34)
                CDMetric(value: String(describing: state.total),
                         label: NSLocalizedString("全部", comment: ""),
                         tint: .primary)
            }

            HStack(spacing: 10) {
                Button {
                    inbox.markAllRead()
                } label: {
                    Label(NSLocalizedString("全部已读", comment: ""), systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(canMarkAllRead ? .white : Color.secondary)
                        .background {
                            if canMarkAllRead {
                                CDTheme.brandGradient
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                CDTheme.cardMuted
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                }
                .buttonStyle(CDCardButtonStyle())
                .disabled(!canMarkAllRead)

                Button {
                    confirmClearAll = true
                } label: {
                    Label(NSLocalizedString("清除全部", comment: ""), systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(canClearAll ? CDTheme.danger : Color.secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(canClearAll ? CDTheme.danger.opacity(0.10) : CDTheme.cardMuted)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(canClearAll ? CDTheme.danger.opacity(0.22) : CDTheme.stroke,
                                              lineWidth: 1)
                        }
                }
                .buttonStyle(CDCardButtonStyle())
                .disabled(!canClearAll)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [CDTheme.accent.opacity(0.13), CDTheme.brandEnd.opacity(0.07)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: CDTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CDTheme.cardRadius, style: .continuous)
                .strokeBorder(CDTheme.accent.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 7)
    }

    @ViewBuilder
    private var banners: some View {
        if state.readSaveFailed {
            CDBanner(kind: .error,
                     message: NSLocalizedString("无法保存本地阅读状态，请重试。", comment: ""))
        }
        if state.deleteFailed {
            CDBanner(kind: .error,
                     message: NSLocalizedString("无法删除这条公告，请重试。", comment: ""))
        }
        if state.failed && session.announcementsConnected {
            CDBanner(kind: .warning,
                     message: NSLocalizedString("公告加载失败，请重试。", comment: ""),
                     actionTitle: NSLocalizedString("重试", comment: ""),
                     action: { session.refreshAnnouncements() })
        }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if state.items.isEmpty {
            if state.loading && !state.loaded {
                HStack {
                    Spacer()
                    ProgressView(NSLocalizedString("加载中…", comment: ""))
                    Spacer()
                }
                .cdCard(padding: 22, elevated: false)
            } else if state.loaded && state.total == 0 && !state.failed {
                CDEmptyState(systemImage: "tray",
                             title: NSLocalizedString("暂无公告", comment: ""),
                             message: session.announcementsConnected
                                ? nil
                                : NSLocalizedString("连接服务器后可获取最新公告。", comment: ""))
                    .cdCard(padding: 20, elevated: false)
            } else if !state.loaded && !session.announcementsConnected {
                CDEmptyState(systemImage: "wifi.slash",
                             title: NSLocalizedString("暂无公告", comment: ""),
                             message: NSLocalizedString("连接服务器后可获取最新公告。", comment: ""))
                    .cdCard(padding: 20, elevated: false)
            }
        } else {
            ForEach(state.items) { item in
                NavigationLink(value: HomeDestination.announcement(
                    AnnouncementSelection(id: item.id, revision: item.revision))) {
                    AnnouncementRow(item: item)
                }
                .buttonStyle(CDCardButtonStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDelete = item
                    } label: {
                        Label(NSLocalizedString("删除公告", comment: ""), systemImage: "trash")
                    }
                }
            }

            if state.loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("加载中…", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            } else if state.items.count < state.total && !state.failed {
                Button {
                    inbox.loadMore()
                } label: {
                    Text(NSLocalizedString("加载更多", comment: ""))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CDTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(CDCardButtonStyle())
                .disabled(!session.announcementsConnected)
                .onAppear { inbox.loadMore() }
            }
        }
    }
}

private struct AnnouncementRow: View {
    let item: Announcement

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.read ? Color.clear : CDTheme.unread)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: item.title)
                    .font(.system(size: 15, weight: item.read ? .regular : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(AnnouncementDate.string(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !item.read {
                        CDPill(text: NSLocalizedString("未读", comment: ""),
                               tint: CDTheme.unread,
                               compact: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(item.read ? CDTheme.stroke : CDTheme.unread.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(item.read ? 0.03 : 0.06),
                radius: item.read ? 8 : 14,
                x: 0,
                y: item.read ? 3 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.read ? NSLocalizedString("已读", comment: "") : NSLocalizedString("未读", comment: ""))
    }
}

struct AnnouncementDetailView: View {
    @ObservedObject var inbox: AnnouncementInbox
    let selection: AnnouncementSelection
    @Environment(\.openURL) private var openURL

    private var item: Announcement? {
        inbox.state.items.first { $0.id == selection.id && $0.revision == selection.revision }
    }

    var body: some View {
        ZStack {
            CDCanvasBackground()

            ScrollView(.vertical) {
                if let item {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: item.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text(AnnouncementDate.string(item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                CDPill(text: NSLocalizedString(item.read ? "已读" : "未读", comment: ""),
                                       tint: item.read ? CDTheme.success : CDTheme.unread,
                                       compact: true)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cdCard(padding: 18)

                        if inbox.state.readSaveFailed {
                            CDBanner(kind: .error,
                                     message: NSLocalizedString("无法保存本地阅读状态，请重试。", comment: ""),
                                     actionTitle: NSLocalizedString("重试保存阅读状态", comment: ""),
                                     action: { inbox.markRead(item) })
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            if item.body.isEmpty {
                                if inbox.state.loading {
                                    HStack {
                                        ProgressView()
                                        Text(NSLocalizedString("加载中…", comment: ""))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if inbox.connected {
                                    Button(NSLocalizedString("重试", comment: "")) { inbox.markRead(item) }
                                        .font(.footnote.weight(.semibold))
                                } else {
                                    Text(NSLocalizedString("连接服务器后可获取最新公告。", comment: ""))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(AnnouncementText.format(item.body))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .environment(\.openURL, OpenURLAction { url in
                                    guard AnnouncementText.isWebURL(url) else { return .discarded }
                                    openURL(url)
                                    return .handled
                                })
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cdCard(padding: 18, elevated: false)
                    }
                    .padding(.horizontal, CDTheme.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .readableContentWidth()
                } else {
                    CDEmptyState(systemImage: "questionmark.folder",
                                 title: NSLocalizedString("这条公告已更新或删除，请返回公告列表查看。", comment: ""))
                        .cdCard(padding: 8, elevated: false)
                        .padding(.horizontal, CDTheme.gutter)
                        .padding(.top, 24)
                        .readableContentWidth()
                }
            }
        }
        .navigationTitle(NSLocalizedString("公告详情", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let item { inbox.markRead(item) }
        }
    }
}
