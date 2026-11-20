import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @StateObject private var location = LocationService.shared

    /// Ponto escolhido no mapa (ainda não aplicado).
    @State private var pin = CLLocationCoordinate2D(latitude: -23.561414, longitude: -46.655881) // Av. Paulista
    @State private var position: MapCameraPosition = .automatic
    @State private var isMoving = false
    @State private var currentSpan = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var shareItem: ShareItem?
    @State private var banner: String?
    @State private var didCenterOnStart = false

    private let mapSpace = "map"

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            searchBar
                .padding(.horizontal)
                .padding(.top, 8)

            VStack {
                Spacer()
                if let banner {
                    Text(banner)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 6)
                }
                controlPanel
            }
        }
        .onAppear {
            location.requestPermissionAndStart()
            if let saved = location.simulatedCoordinate { pin = saved }
            moveCamera(to: pin, animated: false, meters: 1500)
        }
        .onReceive(location.$realLocation) { real in
            // Na primeira leitura do GPS (sem simulação salva), leva o pin até você.
            guard !didCenterOnStart, let real, !location.isSimulating else { return }
            didCenterOnStart = true
            moveCamera(to: real.coordinate, animated: true, meters: 1500)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Mapa + pin fixo no centro

    private var mapLayer: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                    if let active = location.simulatedCoordinate {
                        Annotation("Localização ativa", coordinate: active, anchor: .center) {
                            ActiveLocationDot()
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                // O ponto escolhido é sempre o centro do mapa, onde fica o pin.
                .onMapCameraChange(frequency: .continuous) { context in
                    pin = context.region.center
                    if !isMoving { isMoving = true }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    pin = context.region.center
                    currentSpan = context.region.span
                    isMoving = false
                    haptic(.light)
                }
                .onTapGesture(coordinateSpace: .named(mapSpace)) { point in
                    // Toque no mapa: leva aquele ponto até o pin.
                    if let c = proxy.convert(point, from: .named(mapSpace)) {
                        moveCamera(to: c, animated: true)
                    }
                }

                CenterPin(isLifted: isMoving)
                    .offset(y: -CenterPin.height / 2) // a ponta fica exatamente no centro
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(mapSpace))
        }
    }

    private func moveCamera(to c: CLLocationCoordinate2D, animated: Bool, meters: Double? = nil) {
        pin = c
        let region: MKCoordinateRegion
        if let meters {
            region = MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters)
        } else {
            region = MKCoordinateRegion(center: c, span: currentSpan)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    // MARK: - Busca

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar endereço ou lugar", text: $searchText)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if isSearching {
                ProgressView()
            } else if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: pin, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return show("Nada encontrado") }
            moveCamera(to: item.placemark.coordinate, animated: true, meters: 1200)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } catch {
            show("Nada encontrado")
        }
    }

    // MARK: - Painel inferior

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arraste o mapa para escolher o ponto").font(.caption).foregroundStyle(.secondary)
                    Text(format(pin))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = format(pin)
                    show("Coordenadas copiadas")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copiar coordenadas")
                Button {
                    if let real = location.realLocation?.coordinate {
                        moveCamera(to: real, animated: true)
                    } else {
                        show("Sem sinal de GPS ainda")
                    }
                } label: {
                    Image(systemName: "location")
                }
                .padding(.leading, 10)
                .accessibilityLabel("Ir para minha localização real")
            }

            statusRow

            Button {
                location.apply(pin)
                haptic(.heavy)
                show("Localização aplicada")
            } label: {
                Label("Aplicar localização", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.label))
            .foregroundStyle(Color(.systemBackground))
            .controlSize(.large)

            HStack(spacing: 10) {
                Button {
                    exportGPX()
                } label: {
                    Label("Exportar .gpx", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if location.isSimulating {
                    Button {
                        location.clearSimulation()
                        show("Voltou ao GPS real")
                    } label: {
                        Label("GPS real", systemImage: "location.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .tint(Color(.label))
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(location.isSimulating ? Color.primary : Color.secondary)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(location.isSimulating ? "Localização ativa: simulada" : "Localização ativa: GPS real")
                    .font(.subheadline.weight(.semibold))
                Text(activeDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeDescription: String {
        if let c = location.currentLocation?.coordinate { return format(c) }
        switch location.authorizationStatus {
        case .denied, .restricted: return "Permissão de localização negada"
        case .notDetermined: return "Aguardando permissão…"
        default: return "Buscando sinal de GPS…"
        }
    }

    // MARK: - Helpers

    private func exportGPX() {
        do {
            shareItem = ShareItem(url: try GPXExporter.writeFile(for: pin))
        } catch {
            show("Não foi possível gerar o .gpx")
        }
    }

    private func format(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }

    private func show(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { if banner == message { banner = nil } }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Componentes

/// Pin fixo no centro da tela. Quem se move é o mapa.
struct CenterPin: View {
    static let height: CGFloat = 56
    var isLifted: Bool

    private let ink = Color(white: 0.12)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sombra/alvo no chão marcando o ponto exato.
            Ellipse()
                .fill(Color.black.opacity(0.25))
                .frame(width: isLifted ? 14 : 10, height: isLifted ? 5 : 4)
                .offset(y: 2)

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(ink).frame(width: 34, height: 34)
                    Circle().stroke(Color.white, lineWidth: 3).frame(width: 34, height: 34)
                    Circle().fill(Color.white).frame(width: 11, height: 11)
                }
                Rectangle().fill(ink).frame(width: 3, height: 20)
            }
            .offset(y: isLifted ? -10 : 0)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .frame(width: 40, height: Self.height, alignment: .bottom)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLifted)
        .accessibilityHidden(true)
    }
}

struct ActiveLocationDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(.label).opacity(0.12)).frame(width: 44, height: 44)
            Circle().fill(Color(.systemBackground)).frame(width: 20, height: 20)
            Circle().fill(Color(.label)).frame(width: 13, height: 13)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
