import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var manager: DantroleneManager

    var body: some View {
        VStack(spacing: 0) {
            statusSection

            Divider()

            modeSection

            if manager.mode != .off {
                Divider()

                displaySleepSection
            }

            Divider()

            homeNetworkSection

            Divider()

            launchAtLoginSection

            Divider()

            quitSection
        }
        .frame(width: 280)
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: manager.isPreventingLock ? "pill.fill" : "pill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(manager.isPreventingLock ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.statusText)
                    .font(.system(size: 13, weight: .semibold))

                Text(manager.detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            locationActionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var locationActionButton: some View {
        switch manager.locationState {
        case .notDetermined:
            Button("Grant Access") {
                manager.requestLocationAccess()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .denied:
            Button("Open Settings\u{2026}") {
                manager.openLocationSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .authorized:
            EmptyView()
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $manager.mode) {
                ForEach(DantroleneManager.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Display Sleep

    private var displaySleepSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display Sleep")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Display Sleep", selection: displaySleepBinding) {
                Text("Match System").tag(0)
                Text("1 minute").tag(1)
                Text("2 minutes").tag(2)
                Text("3 minutes").tag(3)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("45 minutes").tag(45)
                Text("1 hour").tag(60)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var displaySleepBinding: Binding<Int> {
        Binding(
            get: { manager.displaySleepMode.tag },
            set: { manager.displaySleepMode = .init(tag: $0) }
        )
    }

    // MARK: - Home Network

    private var homeNetworkSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Home Network")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if let homeSSID = manager.homeSSID {
                    Text(homeSSID)
                        .font(.system(size: 13))
                } else {
                    Text("Not set")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if manager.homeSSID != nil {
                Button("Clear") {
                    manager.clearHomeNetwork()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if manager.currentSSID != nil {
                Button("Use Current") {
                    manager.setCurrentAsHome()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isOnHomeNetwork)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Launch at Login

    private var launchAtLoginSection: some View {
        HStack {
            Text("Launch at Login")
                .font(.system(size: 13))

            Spacer()

            Toggle("", isOn: $manager.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Quit

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit Dantrolene")
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(PopoverMenuItemStyle())
        .keyboardShortcut("q")
        .padding(4)
    }
}

// MARK: - Hover Button Style

private struct PopoverMenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PopoverMenuItemBody(configuration: configuration)
    }

    private struct PopoverMenuItemBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onHover { isHovered = $0 }
        }
    }
}
