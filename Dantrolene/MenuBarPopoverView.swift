import SwiftUI

/// The window-style popover attached to the menu-bar status item.
///
/// One minimal main page — hero, mode, display sleep — with everything deeper pushed as a page
/// *inside* the popover (Adrafinil's pattern; the app has no settings window). The window always
/// hugs the current page's content: pages swap inside one animated transaction, so the
/// `MenuBarExtra` window glides to each page's natural height rather than reserving a maximum.
struct MenuBarPopoverView: View {
    @Bindable var manager: DantroleneManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Page {
        case main
        case settings
        case network
        case lidCloseSleep
    }

    @State private var page: Page = .main
    /// Pages already visited, so Back returns to where the user actually came from — subpages are
    /// reachable both through Settings and directly from the main page's footer chips.
    @State private var stack: [Page] = []
    /// Direction of the last navigation, for the push/pop slide asymmetry.
    @State private var pushing = true

    var body: some View {
        GlassEffectContainer(spacing: Theme.Space.md) {
            ZStack(alignment: .top) {
                switch page {
                case .main:
                    mainPage.transition(pageTransition)
                case .settings:
                    SettingsPage(manager: manager, onBack: pop, onNavigate: push)
                        .transition(pageTransition)
                case .network:
                    NetworkPage(manager: manager, onBack: pop)
                        .transition(pageTransition)
                case .lidCloseSleep:
                    #if !APPSTORE
                        LidSleepPage(manager: manager, onBack: pop)
                            .transition(pageTransition)
                    #endif
                }
            }
            .padding(Theme.Space.lg)
        }
        .frame(width: Theme.popoverWidth)
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: page)
        .onAppear {
            manager.refreshAdrafinilDetection()
        }
        // Reopening always lands on the main page, never on a stale subpage.
        .onDisappear {
            page = .main
            stack = []
            pushing = true
        }
    }

    // MARK: - Navigation

    private func push(_ destination: Page) {
        stack.append(page)
        pushing = true
        page = destination
    }

    private func pop() {
        pushing = false
        page = stack.popLast() ?? .main
    }

    private var pageTransition: AnyTransition {
        pushing
            ? .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity),
            )
            : .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity),
            )
    }

    // MARK: - Main page

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            heroCard
            modeRow

            if showsSetupCard {
                setupCard
            }
            if let permission = permissionAction {
                permissionCard(permission)
            }
            if manager.mode != .off {
                displaySleepSection
            }
            #if !APPSTORE
                if !manager.isAdrafinilInstalled {
                    adrafinilHint
                }
            #endif

            bottomBar
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("Dantrolene")
                .font(.heroTitle)
            Spacer()
            AttributionLink()
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        HStack(spacing: Theme.Space.md) {
            // The state icon folds between house and padlock via true path interpolation —
            // symbol replace transitions can't morph unannotated custom symbols.
            MorphingMark(
                progress: manager.isPreventingLock ? 0 : 1,
                animation: reduceMotion ? nil : .smooth(duration: 0.45),
            )
            .foregroundStyle(manager.isPreventingLock ? Theme.active : .secondary)
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(heroTitle)
                    .font(.cardTitle)
                // Two lines are always reserved so one- and two-line subtitles give the card the
                // same height — the mode row below stays put across states.
                Text(heroSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: manager.isPreventingLock ? Theme.active.opacity(0.18) : nil)
    }

    private var heroTitle: String {
        switch manager.mode {
        case .off: "Off"
        default: manager.isPreventingLock ? "Preventing lock" : "Locking normally"
        }
    }

    private var heroSubtitle: String {
        switch manager.locationState {
        case .notDetermined: return "Needs Location access to read Wi‑Fi names"
        case .denied: return "Location access denied — can't read Wi‑Fi names"
        case .authorized: break
        }
        switch manager.mode {
        case .off:
            return "Your Mac locks and sleeps as usual"
        case .alwaysOn:
            return "Always on — preventing lock on every network"
        case .automatic:
            guard let current = manager.currentSSID else { return "Not connected to Wi‑Fi" }
            guard manager.homeSSID != nil else { return "No home network set — locking as usual" }
            return manager.isOnHomeNetwork
                ? "On \(current) — your home Wi‑Fi"
                : "Away from home — locking as usual"
        }
    }

    // MARK: Mode

    private var modeRow: some View {
        PillPicker(
            title: "Mode",
            options: DantroleneManager.Mode.allCases.map { ($0, $0.rawValue) },
            selection: $manager.mode,
            height: 32,
        )
    }

    // MARK: Setup / permission cards

    /// Show the home-network setup card only when it's the one thing standing between the user
    /// and the app working: automatic mode, Wi-Fi connected, nothing marked as home yet.
    private var showsSetupCard: Bool {
        manager.mode == .automatic && manager.locationState == .authorized
            && manager.homeSSID == nil && manager.currentSSID != nil
    }

    private var setupCard: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Set your home network")
                    .font(.body)
                Text("The lock is only prevented on Wi‑Fi you mark as home")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button("Choose…") {
                push(.network)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.active)
            .foregroundStyle(Theme.onActive)
        }
        .padding(Theme.Space.md)
        .glassCard()
    }

    private struct PermissionAction {
        let message: String
        let button: String
        let action: () -> Void
    }

    private var permissionAction: PermissionAction? {
        switch manager.locationState {
        case .notDetermined:
            PermissionAction(
                message: "Wi‑Fi names are read through Location Services.",
                button: "Grant Access", action: manager.requestLocationAccess,
            )
        case .denied:
            PermissionAction(
                message: "Allow Location access in System Settings to read Wi‑Fi names.",
                button: "Open Settings…", action: manager.openLocationSettings,
            )
        case .authorized:
            nil
        }
    }

    private func permissionCard(_ permission: PermissionAction) -> some View {
        HStack(spacing: Theme.Space.md) {
            Text(permission.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(permission.button, action: permission.action)
                .buttonStyle(.glassProminent)
                .tint(Theme.active)
                .foregroundStyle(Theme.onActive)
        }
        .padding(Theme.Space.md)
        .glassCard()
    }

    // MARK: Display sleep

    /// The chip values always on offer; a custom value set through an older build (e.g. 45 min)
    /// joins the row in sorted position so the selection is never invisible.
    private static let sleepChipMinutes = [1, 5, 10, 30, 60]

    private var sleepChipValues: [DisplaySleepMode] {
        var minutes = Self.sleepChipMinutes
        if case let .custom(current) = manager.displaySleepMode, !minutes.contains(current) {
            minutes.append(current)
            minutes.sort()
        }
        return [.matchSystem] + minutes.map { .custom(minutes: $0) }
    }

    private var displaySleepSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Display Sleep")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            PillPicker(
                title: "Display sleep timeout",
                options: sleepChipValues.map { ($0.tag, chipLabel($0)) },
                selection: displaySleepTagBinding,
                height: 26,
                font: .caption,
            )
        }
    }

    private var displaySleepTagBinding: Binding<Int> {
        Binding(
            get: { manager.displaySleepMode.tag },
            set: { manager.displaySleepMode = .init(tag: $0) },
        )
    }

    private func chipLabel(_ value: DisplaySleepMode) -> String {
        switch value {
        case .matchSystem: "System"
        case let .custom(minutes): minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m"
        }
    }

    // MARK: Adrafinil hint

    #if !APPSTORE
        private var adrafinilHint: some View {
            Button {
                push(.lidCloseSleep)
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    // The dot sits in the same 12pt slot, on the same leading inset, as the
                    // footer chip's Wi-Fi glyph below it, so the two share a vertical axis.
                    StatusDot(color: Theme.adrafinilAmber, diameter: 6)
                        .frame(width: 12)
                    Text("Block lid-close sleep too — works with Adrafinil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .padding(.trailing, Theme.Space.xs)
        }
    #endif

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Theme.Space.sm) {
            metaChips
            Spacer(minLength: 0)
            HStack(spacing: Theme.Space.sm) {
                Button {
                    push(.settings)
                } label: {
                    utilityIcon("gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    utilityIcon("xmark")
                }
                .keyboardShortcut("q")
                .help("Quit Dantrolene")
                .accessibilityLabel("Quit Dantrolene")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    /// Wi-Fi and lid-hold chips — glass pills, so they read as the navigation shortcuts they are.
    private var metaChips: some View {
        HStack(spacing: Theme.Space.sm) {
            if let ssid = manager.currentSSID {
                FooterChip(text: ssid, systemImage: "wifi") {
                    push(.network)
                }
                .help("Home Network")
            }
            #if !APPSTORE
                if manager.isBlockingLidCloseSleep {
                    FooterChip(text: "Lid hold", systemImage: "laptopcomputer.slash") {
                        push(.lidCloseSleep)
                    }
                    .help("Lid-Close Sleep")
                }
            #endif
        }
    }

    /// A glyph for the bottom-bar utility buttons, pinned to a fixed square so both `.glass`
    /// capsules come out the same size regardless of glyph proportions.
    private func utilityIcon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 16, height: 16)
    }
}

// MARK: - Footer chip

/// A caption-sized glass pill that doubles as navigation into its page.
private struct FooterChip: View {
    let text: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(text)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

// MARK: - Attribution

private struct AttributionLink: View {
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://github.com/kageroumado")!) {
            HStack(spacing: 2) {
                Text("made by kageroumado")
                    .underline(hovering)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
