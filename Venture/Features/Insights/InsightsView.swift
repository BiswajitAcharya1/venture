import SwiftUI

struct InsightsView: View {
    let store: VentureStore
    @State private var expandedGroup = ""

    private var screeningResults: [SupabaseScreeningResult] {
        SupabaseModelSyncBatchBuilder.screeningResults(from: store.metricGroups)
            + SupabaseModelSyncBatchBuilder.forecastResults(from: store.mentalHealthSummary.forecasts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("measured evidence")
                        .font(.system(.largeTitle, design: .serif, weight: .regular))
                    Text("only completed tasks and connected health samples appear here.")
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                }

                if !store.isReady {
                    EvidenceSkeletonView()
                        .transition(.opacity)
                } else if store.metricGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("No evidence yet").font(.title3)
                        Text("Complete a check-in or connect Apple Health. Skipped and unavailable measurements will not be filled in.")
                            .font(.caption)
                            .foregroundStyle(VentureTheme.secondary)
                    }
                    .padding(.vertical, 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.metricGroups) { group in
                            DisclosureGroup(isExpanded: binding(for: group.id)) {
                                VStack(spacing: 0) {
                                    ForEach(group.metrics) { metric in
                                        metricRow(metric)
                                        if metric.id != group.metrics.last?.id { Divider() }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.title).font(.system(.title3, design: .serif, weight: .medium))
                                    Text(group.summary).font(.caption2).foregroundStyle(VentureTheme.secondary)
                                }
                            }
                            .tint(VentureTheme.secondary)
                            .padding(.vertical, 17)
                            if group.id != store.metricGroups.last?.id { Divider() }
                        }
                    }
                }

                ScreeningOutputsSection(results: screeningResults)
                Text("personal comparisons appear only after enough repeated measurements exist. venture does not diagnose.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(VentureAtmosphereView().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroup == id },
            set: { expandedGroup = $0 ? id : "" }
        )
    }

    private func metricRow(_ metric: Metric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name).font(.caption)
                Text(metric.baseline.map { "personal reference \($0.formatted(.number.precision(.fractionLength(1))))\(metric.unit)" } ?? "learning personal reference")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Spacer()
            Text("\(metric.value.formatted(.number.precision(.fractionLength(1))))\(metric.unit)")
                .font(.caption.monospacedDigit())
        }
        .padding(.vertical, 10)
    }
}

private struct ScreeningOutputsSection: View {
    let results: [SupabaseScreeningResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("screening outputs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VentureTheme.secondary)
                Spacer()
                Text(results.isEmpty ? "waiting" : "\(results.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(VentureTheme.secondary)
            }

            if results.isEmpty {
                ScreeningOutputSkeleton()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        ScreeningOutputRow(result: result)
                        if index < results.count - 1 { Divider().opacity(0.45) }
                    }
                }
                .padding(.horizontal, 14)
                .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct ScreeningOutputRow: View {
    let result: SupabaseScreeningResult

    private var model: RuntimeModelArtifact? {
        ModelRuntimeManifest.all.first { $0.id == result.modelID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label.lowercased())
                        .font(.subheadline.weight(.semibold))
                    Text(model?.displayName.lowercased() ?? result.modelID)
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                Spacer()
                if let likelihood = result.likelihoodPercent {
                    Text("\(likelihood.formatted(.number.precision(.fractionLength(likelihood.rounded() == likelihood ? 0 : 1))))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    Text(result.outputType.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(VentureTheme.secondary)
                }
            }

            HStack(spacing: 7) {
                statusPill(model?.state.rawValue ?? "sourceBound")
                statusPill(model?.runtime.rawValue.lowercased() ?? "app-native")
            }

            if let evidence = result.evidence.first {
                Text(evidence.lowercased())
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = result.action {
                Text(action.lowercased())
                    .font(.caption2.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(VentureTheme.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VentureTheme.surface, in: Capsule())
    }
}

private struct ScreeningOutputSkeleton: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(VentureTheme.ink.opacity(pulse ? 0.09 : 0.045))
                        .frame(width: index == 1 ? 190 : 145, height: 11)
                    Capsule()
                        .fill(VentureTheme.ink.opacity(pulse ? 0.065 : 0.032))
                        .frame(maxWidth: .infinity)
                        .frame(height: 9)
                }
                .padding(.vertical, 6)
            }
            Text("complete a scan or import health data to create measured screening outputs.")
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
        }
        .padding(14)
        .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("waiting for measured screening outputs")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct EvidenceSkeletonView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 13) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    Capsule()
                        .fill(VentureTheme.ink.opacity(pulse ? 0.11 : 0.06))
                        .frame(width: index.isMultiple(of: 2) ? 132 : 96, height: 12)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(VentureTheme.ink.opacity(pulse ? 0.075 : 0.035))
                        .frame(height: 52)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
        .accessibilityLabel("loading measured evidence")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
