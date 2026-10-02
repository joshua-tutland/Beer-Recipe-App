import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BrewTimerWidgets: WidgetBundle {
    var body: some Widget {
        BrewTimerLiveActivity()
    }
}

/// Brew-day timer on the Lock Screen and in the Dynamic Island.
struct BrewTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrewTimerAttributes.self) { context in
            LockScreenTimerView(attributes: context.attributes, state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.recipeName, systemImage: "flame.fill")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: context.state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.stepTitle).font(.subheadline).lineLimit(1)
                        UpcomingAdditions(state: context.state, limit: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            } compactTrailing: {
                TimerText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }
}

struct LockScreenTimerView: View {
    let attributes: BrewTimerAttributes
    let state: BrewTimerAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.recipeName).font(.caption).foregroundStyle(.secondary)
                    Text(state.stepTitle).font(.headline).lineLimit(2)
                }
                Spacer()
                TimerText(state: state)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if let end = state.endDate, state.startDate < end {
                ProgressView(timerInterval: state.startDate...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.orange)
            }
            UpcomingAdditions(state: state, limit: 2)
        }
    }
}

/// Live countdown; iOS updates it on its own without the app running.
struct TimerText: View {
    let state: BrewTimerAttributes.ContentState

    var body: some View {
        if let end = state.endDate, state.startDate < end {
            Text(timerInterval: state.startDate...end, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else if let paused = state.pausedRemaining {
            Text("\(Int(paused) / 60):\(String(format: "%02d", Int(paused) % 60)) ❚❚")
        } else {
            Text("Done")
        }
    }
}

struct UpcomingAdditions: View {
    let state: BrewTimerAttributes.ContentState
    let limit: Int

    var body: some View {
        if state.endDate != nil {
            let upcoming = state.additions.filter { $0.date > Date() }.prefix(limit)
            ForEach(Array(upcoming), id: \.self) { addition in
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").foregroundStyle(.green)
                    Text(addition.title).lineLimit(1)
                    Spacer()
                    Text(addition.date, style: .time).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
