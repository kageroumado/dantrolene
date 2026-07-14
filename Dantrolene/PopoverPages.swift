import SwiftUI

// MARK: - Settings

/// The page behind the gear: navigation rows for the deeper surfaces plus the app-level
/// housekeeping that doesn't belong on the main path.
struct SettingsPage: View {
    @Bindable var manager: DantroleneManager
    let onBack: () -> Void
    let onNavigate: (MenuBarPopoverView.Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            NavHeader(title: "Settings", onBack: onBack)

            VStack(spacing: 0) {
                NavRow(title: "Home Network", value: manager.homeSSID ?? "Not set") {
                    onNavigate(.network)
                }
                #if !APPSTORE
                    Divider()
                        .padding(.horizontal, Theme.Space.sm)
                    NavRow(
                        title: "Lid-Close Sleep",
                        value: lidValue,
                        valueColor: manager.isAdrafinilInstalled ? .secondary : Theme.adrafinilAmber,
                    ) {
                        onNavigate(.lidCloseSleep)
                    }
                #endif
            }
            .padding(Theme.Space.xs)
            .glassCard()

            // Same metrics as the NavRows above (xs card inset + sm row padding + 22pt row),
            // so both cards read as one system with equal row heights.
            HStack {
                Text("Launch at Login")
                    .font(.body)
                Spacer()
                Toggle("Launch at Login", isOn: $manager.launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .frame(minHeight: 22)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .padding(Theme.Space.xs)
            .glassCard()
            .accessibilityElement(children: .combine)

            versionFooter
        }
    }

    private var lidValue: String {
        guard manager.isAdrafinilInstalled else { return "Get Adrafinil" }
        return manager.blockLidCloseSleep ? "On" : "Off"
    }

    private var versionFooter: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Version \(BuildChannel.description) ·")
            Link(destination: URL(string: "https://kagerou.glass/dantrolene/")!) {
                Text("made by kageroumado \(Image(systemName: "arrow.up.right"))")
            }
            .buttonStyle(.plain)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Home Network

/// Room the old inline row never had: the connected network with Set as Home, the remembered
/// home network when it differs, and the privacy story in plain words.
struct NetworkPage: View {
    @Bindable var manager: DantroleneManager
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            NavHeader(title: "Home Network", onBack: onBack)

            switch manager.locationState {
            case .notDetermined:
                permissionCard(
                    message: "Dantrolene needs Location access to read Wi‑Fi network names.",
                    button: "Grant Access", action: manager.requestLocationAccess,
                )
            case .denied:
                permissionCard(
                    message: "Location access is denied, so Wi‑Fi names can't be read.",
                    button: "Open Settings…", action: manager.openLocationSettings,
                )
            case .authorized:
                currentNetworkCard
                homeNetworkCard
            }

            Text("Dantrolene only prevents the lock — and only holds your Mac awake — while connected to this network. Nothing is tracked; the name stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xs)
        }
    }

    @ViewBuilder
    private var currentNetworkCard: some View {
        if let current = manager.currentSSID {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(current, systemImage: "wifi")
                        .font(.cardTitle)
                    Text(manager.isOnHomeNetwork ? "Connected — this is your home network" : "Connected now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                if !manager.isOnHomeNetwork {
                    Button("Set as Home") {
                        manager.setCurrentAsHome()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.active)
                    .foregroundStyle(Theme.onActive)
                }
            }
            .padding(Theme.Space.md)
            .glassCard(tint: manager.isOnHomeNetwork ? Theme.active.opacity(0.18) : nil)
        } else {
            Text("Not connected to Wi‑Fi")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.md)
                .glassCard()
        }
    }

    @ViewBuilder
    private var homeNetworkCard: some View {
        if let home = manager.homeSSID {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if manager.isOnHomeNetwork {
                        Text("Stop treating this network as home?")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(home)
                            .font(.body)
                        Text("Home — not in range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button("Clear") {
                    manager.clearHomeNetwork()
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Clear home network")
            }
            .padding(Theme.Space.md)
            .glassCard()
        }
    }

    private func permissionCard(message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.glassProminent)
                .tint(Theme.active)
                .foregroundStyle(Theme.onActive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .glassCard()
    }
}

// MARK: - Lid-Close Sleep

#if !APPSTORE

    /// One destination, two personalities: the toggle when Adrafinil is installed, the promo when
    /// it isn't. Detection refreshes when the popover opens, so this flips without a relaunch.
    struct LidSleepPage: View {
        @Bindable var manager: DantroleneManager
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                NavHeader(title: "Lid-Close Sleep", onBack: onBack)

                if manager.isAdrafinilInstalled {
                    toggleCard
                    if manager.isBlockingLidCloseSleep {
                        statusLine
                    }
                    caption(
                        "Dantrolene asks Adrafinil to keep the Mac awake when the lid closes, and releases the hold the moment you leave home, switch modes, or quit.",
                    )
                } else {
                    promoCard
                    caption(
                        "Free & open source. Dantrolene detects it automatically — this page becomes the toggle once it's installed.",
                    )
                }
            }
        }

        private var isActive: Bool {
            manager.isBlockingLidCloseSleep
        }

        private var toggleCard: some View {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block lid-close sleep")
                        .font(.body)
                    Text("While on your home Wi‑Fi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Toggle("Block lid-close sleep", isOn: $manager.blockLidCloseSleep)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(Theme.Space.md)
            .glassCard(tint: isActive ? Theme.active.opacity(0.18) : nil)
            .accessibilityElement(children: .combine)
        }

        private var statusLine: some View {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(color: manager.isLidCloseHoldConfirmed ? .green : .orange)
                Text(
                    manager.isLidCloseHoldConfirmed
                        ? "Active — holding via Adrafinil"
                        : "Adrafinil isn't responding — retrying",
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.xs)
        }

        private var promoCard: some View {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.md) {
                    SpiralEyeGlyph()
                        .frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Works with Adrafinil")
                            .font(.cardTitle)
                        Text("by the same developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Adrafinil keeps your Mac awake while AI agents work. When it's installed, Dantrolene can borrow its engine to block lid-close sleep on your home Wi‑Fi — close the MacBook, stay unlocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://kagerou.glass/adrafinil/")!) {
                    Text("Get Adrafinil \(Image(systemName: "arrow.up.right"))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.adrafinilAmber)
            }
            .padding(Theme.Space.md)
            .glassCard(tint: Theme.adrafinilAmber.opacity(0.14))
        }

        private func caption(_ text: String) -> some View {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xs)
        }
    }

    /// Adrafinil's spiral-eye mark, approximated as a logarithmic spiral with a pupil — enough to
    /// be recognizable on the promo card without importing the real asset.
    struct SpiralEyeGlyph: View {
        var body: some View {
            GeometryReader { proxy in
                let s = min(proxy.size.width, proxy.size.height) / 32
                SpiralShape()
                    .stroke(
                        Theme.adrafinilAmber,
                        style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round),
                    )
                    .overlay {
                        Circle()
                            .fill(Theme.adrafinilAmber.mix(with: .black, by: 0.6))
                            .frame(width: 5.2 * s, height: 5.2 * s)
                            .position(x: 14.6 * s, y: 17.2 * s)
                    }
            }
        }

        private struct SpiralShape: Shape {
            nonisolated func path(in rect: CGRect) -> Path {
                let s = min(rect.width, rect.height) / 32
                var path = Path()
                let points = (0 ... 90).map { i -> CGPoint in
                    let theta = CGFloat(i) / 90 * 2.4 * .pi
                    let r = 1.6 * exp(0.30 * theta)
                    return CGPoint(
                        x: (16 + r * cos(theta + 2.4)) * s + rect.minX,
                        y: (16 - r * sin(theta + 2.4)) * s + rect.minY,
                    )
                }
                path.addLines(points)
                return path
            }
        }
    }

#endif

// MARK: - Shared page chrome

/// Back button + rounded page title, the header of every pushed page.
struct NavHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm + 2) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Back")

            Text(title)
                .font(.heroTitle)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
    }
}

/// A settings-style navigation row: title, current value, chevron, hover fill.
struct NavRow: View {
    let title: String
    let value: String
    var valueColor: Color = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(valueColor)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 22)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.controlShape.fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Theme.controlShape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A small filled state indicator (from Adrafinil's design system).
struct StatusDot: View {
    let color: Color
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
    }
}
