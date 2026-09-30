import SwiftUI
import UIKit
import BrewCore

/// Step-by-step brew day, generated from the recipe, with countdown timers and a boil schedule.
struct BrewDayChecklistView: View {
    @Binding var session: BrewSession
    let recipe: Recipe
    let units: UnitSystem

    @Environment(BrewTimers.self) private var timers
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    private var steps: [BrewStep] { BrewDayPlan.steps(for: recipe, units: units) }

    var body: some View {
        let steps = self.steps
        let done = steps.filter { session.isStepDone($0.id) }.count

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(done) of \(steps.count) steps done")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if done == steps.count {
                            Label("Complete", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                    }
                    ProgressView(value: Double(done), total: Double(max(steps.count, 1)))
                        .tint(.brewAmber)
                }
                Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
            }

            ForEach(BrewPhase.allCases, id: \.self) { phase in
                let phaseSteps = steps.filter { $0.phase == phase }
                if !phaseSteps.isEmpty {
                    Section {
                        ForEach(phaseSteps) { step in
                            StepRow(step: step, session: $session,
                                    timerKey: BrewTimers.key(session: session.id, step: step.id))
                        }
                    } header: {
                        Label(phase.displayName, systemImage: phase.symbol)
                    }
                }
            }
        }
        .navigationTitle("Brew Day")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
        .onChange(of: keepScreenAwake) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct StepRow: View {
    let step: BrewStep
    @Binding var session: BrewSession
    let timerKey: String

    @Environment(BrewTimers.self) private var timers

    private var isDone: Bool { session.isStepDone(step.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation { session.setStep(step.id, done: !isDone) }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isDone ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDone ? "Mark not done" : "Mark done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    if let detail = step.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let minutes = step.durationMinutes, !isDone {
                StepTimerView(step: step, minutes: minutes, timerKey: timerKey, session: $session)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StepTimerView: View {
    let step: BrewStep
    let minutes: Double
    let timerKey: String
    @Binding var session: BrewSession

    @Environment(BrewTimers.self) private var timers

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timer = timers.timer(timerKey, duration: minutes * 60)
            let remaining = timer.remaining(at: context.date)
            let finished = timer.isFinished(at: context.date)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(StepTimer.format(remaining))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(finished ? Color.green : (timer.isRunning ? Color.brewAmber : Color.primary))
                        .contentTransition(.numericText(countsDown: true))
                    Spacer()
                    if finished {
                        Button("Done", systemImage: "checkmark") {
                            session.setStep(step.id, done: true)
                            timers.reset(timerKey)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if timer.isRunning {
                        Button("Pause", systemImage: "pause.fill") { timers.pause(timerKey) }
                            .buttonStyle(.bordered)
                    } else {
                        Button(timer.isPaused ? "Resume" : "Start", systemImage: "play.fill") {
                            timers.start(timerKey, step: step)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brewAmber)
                    }
                    if !timer.isIdle {
                        Button("Reset", systemImage: "arrow.counterclockwise") { timers.reset(timerKey) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                    }
                }
                ProgressView(value: timer.progress(at: context.date))
                    .tint(finished ? Color.green : Color.brewAmber)

                if !step.alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(step.alerts) { alert in
                            AlertRow(alert: alert, remaining: remaining, started: !timer.isIdle,
                                     done: session.isStepDone(alertID(alert))) { newValue in
                                session.setStep(alertID(alert), done: newValue)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.borderless)  // lets each button in the row be tapped separately
    }

    private func alertID(_ alert: TimedAlert) -> String { "\(step.id)/\(alert.id)" }
}

/// One scheduled addition within a timed step.
private struct AlertRow: View {
    let alert: TimedAlert
    let remaining: TimeInterval
    let started: Bool
    let done: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        let due = started && remaining <= alert.minutesRemaining * 60
        HStack(spacing: 10) {
            Button {
                toggle(!done)
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.green : (due ? Color.orange : Color.secondary))
            }
            .buttonStyle(.plain)
            Text(alert.title)
                .font(.subheadline)
                .strikethrough(done)
                .foregroundStyle(done ? Color.secondary : Color.primary)
            Spacer()
            if due && !done {
                Text("Now")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background((due && !done ? Color.orange.opacity(0.12) : Color(.tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}
