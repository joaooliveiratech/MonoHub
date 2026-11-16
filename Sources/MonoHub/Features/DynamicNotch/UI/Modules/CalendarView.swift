import SwiftUI
import AppKit
import EventKit

struct CalendarView: View {
    private let calendarManager = CalendarManager.shared
    private let preferences = NotchPreferences.shared

    init() {}

    private var filteredEvents: [CalendarEventItem] {
        let base = calendarManager.remainingEvents.filter { event in
            preferences.calendarShowAllDayEvents || !event.isAllDay
        }
        return Array(base.prefix(max(1, preferences.calendarMaxEventsShown)))
    }

    var body: some View {
        Group {
            if calendarManager.isAuthorized {
                authorizedView
            } else {
                permissionView
            }
        }
        .notchModule()
        .onAppear {
            calendarManager.checkAuthorization(forceFetch: true)
        }
    }

    private var authorizedView: some View {
        HStack(spacing: 16) {
            if let next = calendarManager.nextUpcomingEvent {

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        NotchDateBadge(date: next.startDate, size: 36)

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(next.isNow ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                    .symbolEffect(.pulse, options: .repeat(.continuous), isActive: next.isNow)
                                Text(next.isNow ? localized("HAPPENING NOW") : String(format: localized("UP NEXT • %@"), next.localizedRelativeString.uppercased()))
                                    .font(NotchTheme.eyebrow)
                                    .foregroundStyle(next.isNow ? Color.green : Color.red)
                                    .lineLimit(1)
                            }

                            Text(next.localizedTimeString)
                                .font(NotchTheme.caption.monospacedDigit())
                                .foregroundStyle(NotchTheme.secondaryText)
                        }

                        Spacer(minLength: 2)
                    }

                    Text(next.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let calTitle = next.calendarTitle, !calTitle.isEmpty {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 5, height: 5)
                                Text(calTitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(NotchTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        if let loc = next.location, !loc.isEmpty {
                            Text("• \(loc)")
                                .font(.system(size: 10))
                                .foregroundStyle(NotchTheme.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        if let url = next.meetingURL {
                            Button {
                                NotchHaptics.tap()
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "video.fill")
                                    Text(localized("Join meeting"))
                                }
                            }
                            .buttonStyle(NotchPrimaryButtonStyle(tint: .green, foreground: .black))

                            Button {
                                NotchHaptics.tap()
                                openCalendarApp()
                            } label: {
                                Image(systemName: "calendar")
                            }
                            .buttonStyle(NotchCircleButtonStyle(size: 28, fill: NotchTheme.controlFill, foreground: .white))
                            .help(localized("Open in Calendar"))
                        } else {
                            Button {
                                NotchHaptics.tap()
                                openCalendarApp()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "calendar")
                                    Text(localized("Open in Calendar"))
                                }
                            }
                            .buttonStyle(NotchSecondaryButtonStyle())
                        }
                    }
                }
                .frame(width: 245, alignment: .leading)
                .padding(NotchTheme.cardPadding)
                .notchCardSurface(tint: next.isNow ? .green : .red)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        NotchSectionLabel(
                            String(format: localized("Today's Agenda (%d)"), calendarManager.remainingEvents.count),
                            systemImage: "clock.fill",
                            tint: .red
                        )

                        Spacer()

                        Button {
                            triggerSync()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .symbolEffect(.rotate, isActive: calendarManager.isSyncing)
                                Text(localized("Sync"))
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(NotchTheme.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(localized("Sync events with macOS Calendar"))
                    }

                    let otherEvents = filteredEvents.filter { $0.id != next.id }
                    if otherEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localized("No other events today"))
                                .font(NotchTheme.body)
                                .foregroundStyle(NotchTheme.secondaryText)
                            Text(localized("You are all caught up with your agenda."))
                                .font(NotchTheme.caption)
                                .foregroundStyle(NotchTheme.tertiaryText)
                        }
                        .padding(.top, 8)
                        Spacer()
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(otherEvents) { event in
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                            .fill(event.isNow ? Color.green : Color.red.opacity(0.85))
                                            .frame(width: 3, height: 22)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(event.title)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(NotchTheme.primaryText)
                                                .lineLimit(1)

                                            if let calTitle = event.calendarTitle, !calTitle.isEmpty {
                                                Text(calTitle)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(NotchTheme.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer(minLength: 4)

                                        if let url = event.meetingURL {
                                            Button {
                                                NotchHaptics.tap()
                                                NSWorkspace.shared.open(url)
                                            } label: {
                                                Image(systemName: "video.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.black)
                                                    .padding(5)
                                                    .background(Circle().fill(Color.green))
                                                    .contentShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                            .help(localized("Join meeting"))
                                        }

                                        Text(event.localizedTimeString)
                                            .font(NotchTheme.caption.monospacedDigit())
                                            .foregroundStyle(NotchTheme.secondaryText)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NotchEmptyState(
                    systemImage: "calendar.badge.clock",
                    tint: .red,
                    title: localized("No remaining events today"),
                    message: localized("Your agenda is free for the rest of the day."),
                    actionTitle: localized("Sync agenda")
                ) {
                    triggerSync()
                }
            }
        }
    }

    private var permissionView: some View {
        let isDenied = calendarManager.authorizationStatus == .denied || calendarManager.authorizationStatus == .restricted

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: isDenied ? "calendar.badge.exclamationmark" : "calendar")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .padding(.bottom, 2)

            Text(isDenied ? localized("Calendar access disabled") : localized("Allow Calendar access"))
                .font(NotchTheme.title)
                .foregroundStyle(NotchTheme.primaryText)

            Text(isDenied
                ? localized("Calendar access was denied or disabled. Enable MonoHub in System Settings > Privacy & Security > Calendars to sync your events.")
                : localized("Allow MonoHub to access your calendars to display upcoming meetings and daily agenda directly in the notch."))
                .font(NotchTheme.body)
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    calendarManager.requestAccess()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(isDenied ? localized("Request again") : localized("Allow access"))
                    }
                }
                .buttonStyle(NotchPrimaryButtonStyle(tint: .red, foreground: .white))

                Button {
                    NotchHaptics.tap()
                    calendarManager.openSystemCalendarPrivacySettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                        Text(localized("Open System Settings"))
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func triggerSync() {
        NotchHaptics.tap()
        calendarManager.syncNow()
    }

    private func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
