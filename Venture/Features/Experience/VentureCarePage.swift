import Combine
import CoreLocation
import MapKit
import SwiftUI

@MainActor final class VentureHospitalSearch: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var hospitals: [MKMapItem] = []
    @Published private(set) var searching = false
    @Published private(set) var failed = false
    private let location = CLLocationManager()
    private var search: MKLocalSearch?
    private var requestPending = false
    override init() { super.init(); location.delegate = self; location.desiredAccuracy = kCLLocationAccuracyKilometer }
    func find() {
        guard !searching else { return }
        failed = false; requestPending = true
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: searching = true; location.requestLocation()
        case .notDetermined: location.requestWhenInUseAuthorization()
        default: failed = true
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestPending else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: find()
        case .denied, .restricted: failed = true; requestPending = false; searching = false
        default: break
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard requestPending else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "community health clinic"
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
            request.resultTypes = .pointOfInterest
            search = MKLocalSearch(request: request)
            do {
                let response = try await search!.start()
                guard requestPending else { return }
                hospitals = Array(response.mapItems.prefix(5)); failed = hospitals.isEmpty
            } catch {
                guard requestPending else { return }
                failed = true
            }
            searching = false; requestPending = false
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in guard requestPending else { return }; searching = false; requestPending = false; failed = true }
    }
    func cancel() { requestPending = false; search?.cancel(); searching = false }
}

struct VentureCarePage: View {
    @Bindable var store: VentureStore
    var locale: VentureLocale
    @StateObject private var speech = VentureSpeechService()
    @StateObject private var hospitals = VentureHospitalSearch()
    @ObservedObject var calling: VentureCallingService
    @State private var chosen: MKMapItem?
    @State private var experiment: VentureCallExperiment?
    @State private var liveDemo = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    Text(locale.support(.getHelp)).font(.system(size: 32, weight: .regular, design: .rounded)).tracking(-0.7)
                        .accessibilityIdentifier("help-title")
                    Spacer()
                    Image(systemName: "heart").font(.system(size: 24, weight: .light)).foregroundStyle(VentureCanvas.accent)
                        .frame(width: 54, height: 54).background(VentureCanvas.surface, in: Circle())
                }
                Text(locale.support(.careIntro)).font(.subheadline).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
                supportOption(.voiceCare, .voiceCareNote, "waveform", source: "https://www.nidcd.nih.gov/health/taking-care-your-voice", identifier: "voice-care-option")
                supportOption(.memoryCare, .memoryCareNote, "list.bullet.clipboard", source: "https://www.nia.nih.gov/health/memory-loss-and-forgetfulness/memory-forgetfulness-and-aging-whats-normal-and-whats-not", identifier: "memory-care-option")
                supportOption(.telehealth, .telehealthNote, "phone", source: "https://telehealth.hhs.gov/patients/what-should-i-know-before-my-telehealth-visit", identifier: "telehealth-option")
                supportOption(.visitPlan, .visitPlanNote, "calendar", source: "https://telehealth.hhs.gov/providers/preparing-patients-for-telehealth/helping-patients-prepare-for-their-appointment", identifier: "visit-plan-option")
                clinicSection
                if store.snapshots.last != nil {
                    ShareLink(item: VentureVoiceEvidenceSummary.text(snapshot: store.snapshots.last)) {
                        HStack { Image(systemName: "square.and.arrow.up"); Text(locale.support(.share)); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.subheadline.weight(.medium)).padding(22).ventureSurface(cornerRadius: 24)
                    }.accessibilityIdentifier("share-voice-summary")
                }
                callSupport
                if !locale.hasTranslatedSupport { Text(locale.support(.englishNotice)).font(.caption).foregroundStyle(VentureCanvas.muted) }
            }.padding(28)
        }.scrollIndicators(.hidden).onDisappear { speech.stop(); hospitals.cancel() }
            .sheet(isPresented: $liveDemo) { VentureLiveVoiceDemoView(store: store, locale: locale) }
            .sheet(item: $experiment) { selected in
                VentureCallTestView(experiment: selected, service: calling, store: store,
                                    locale: locale, hospital: chosen?.name, phoneNumber: chosen?.phoneNumber)
            }
    }

    private func supportOption(_ title: VentureSupportCopy, _ note: VentureSupportCopy, _ symbol: String, source: String, identifier: String) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 15) {
                Text(locale.support(note)).font(.subheadline).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
                    .accessibilityIdentifier("\(identifier)-detail")
                Link(destination: URL(string: source)!) {
                    Label(locale.support(.source), systemImage: "arrow.up.right")
                }.font(.footnote.weight(.medium))
            }.padding(.top, 14)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 21, weight: .light)).foregroundStyle(VentureCanvas.accent).frame(width: 27)
                Text(locale.support(title)).font(.subheadline.weight(.medium)).foregroundStyle(VentureCanvas.ink)
            }.padding(.vertical, 3)
        }.padding(22).ventureSurface(cornerRadius: 24).accessibilityIdentifier(identifier)
    }

    private var clinicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(locale.support(.clinic), systemImage: "cross.case").font(.title3.weight(.regular)).foregroundStyle(VentureCanvas.accent)
            Text(locale.support(.clinicNote)).font(.subheadline).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
            Button { hospitals.find() } label: {
                HStack {
                    Image(systemName: "location")
                    Text(locale.support(.clinic))
                    Spacer()
                    if hospitals.searching { ProgressView() } else { Image(systemName: "arrow.right") }
                }.font(.subheadline.weight(.medium)).padding(.vertical, 12)
            }.disabled(hospitals.searching).accessibilityIdentifier("find-clinic")
            Link(destination: URL(string: "https://maps.apple.com/?q=community+health+clinic")!) {
                Label(locale.support(.directions), systemImage: "map")
            }.font(.footnote)
            Link("u.s. community health centers · HRSA", destination: URL(string: "https://findahealthcenter.hrsa.gov/")!)
                .font(.footnote).accessibilityIdentifier("hrsa-health-centers")
            ForEach(Array(hospitals.hospitals.enumerated()), id: \.offset) { _, hospital in
                VStack(alignment: .leading, spacing: 12) {
                    Button { chosen = hospital; Haptics.selected() } label: {
                        HStack { Text(hospital.name ?? locale.support(.clinic)); Spacer(); if chosen === hospital { Image(systemName: "checkmark") } }
                    }.font(.subheadline.weight(.medium))
                    if chosen === hospital {
                        HStack(spacing: 20) {
                            Button { hospital.openInMaps() } label: { Label(locale.support(.directions), systemImage: "map") }
                            if let phone = hospital.phoneNumber, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                                Link(destination: url) { Label(phone, systemImage: "phone") }
                            }
                        }.font(.footnote)
                    }
                }.padding(.top, 14)
            }
            if hospitals.failed { Text(locale.support(.noNearby)).font(.footnote).foregroundStyle(VentureCanvas.muted) }
        }.padding(24).ventureSurface(cornerRadius: 28)
    }

    private var callSupport: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 22) {
                VentureCallExperimentList(service: calling) { selected in
                    speech.stop(); experiment = selected
                }
                Text(locale.t(.demo)).font(.footnote).foregroundStyle(VentureCanvas.muted)
                VentureAction(title: locale.t(.assistant), symbol: "mic") { speech.stop(); liveDemo = true }
                    .accessibilityIdentifier("live-call-demo")
                VentureAction(title: locale.t(speech.playing && !speech.paused ? .pause : .call), symbol: speech.playing && !speech.paused ? "pause.fill" : "play.fill") {
                    speech.speak(script)
                }.disabled(speech.preparing).accessibilityIdentifier("demo-call")
                if speech.preparing { HStack { ProgressView(); Text(locale.t(.preparing)) }.font(.footnote) }
                if speech.failed { Text(locale.t(.unavailable)).font(.footnote) }
                Text(locale.t(.voiceNotice)).font(.caption).foregroundStyle(VentureCanvas.muted)
                Text("Kokoro Core ML").font(.caption).foregroundStyle(VentureCanvas.muted)
            }.padding(.top, 18)
        } label: {
            Label(locale.t(.demo), systemImage: "phone.bubble").font(.subheadline.weight(.medium)).foregroundStyle(VentureCanvas.ink)
        }.padding(22).ventureSurface(cornerRadius: 24).accessibilityIdentifier("appointment-practice")
    }

    private var script: String {
        let destination = chosen?.name.map { " at \($0)" } ?? ""
        let evidence = VentureCallContext.summary(snapshot: store.snapshots.last)
        return "Hello. This is a scripted demonstration of an appointment request\(destination), on behalf of a Venture user. \(evidence) Could you explain how to arrange a routine appointment with a qualified clinician? This is a demonstration, and no real phone call is being made."
    }
}
