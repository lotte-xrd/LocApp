import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @StateObject private var location = LocationService.shared

    /// Ponto escolhido no mapa (ainda não aplicado).
    @State private var pin = CLLocationCoordinate2D(latitude: -23.561414, longitude: -46.655881) // Av. Paulista
    @State private var position: MapCameraPosition = .automatic
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var cameraTick = 0
    @State private var isDragging = false
    @State private var grabOffset: CGSize = .zero

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
            position = .region(MKCoordinateRegion(center: pin, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
        .onReceive(location.$realLocation) { real in
            // Na primeira leitura do GPS (sem simulação salva), leva o pin até você.
            guard !didCenterOnStart, let real, !location.isSimulating else { return }
            didCenterOnStart = true
            pin = real.coordinate
            position = .region(MKCoordinateRegion(center: real.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Mapa + pin arrastável

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
                .onMapCameraChange(frequency: .continuous) { context in
                    mapCenter = context.region.center
                    cameraTick &+= 1 // força o pin a acompanhar o mapa
                }
                .onTapGesture(coordinateSpace: .named(mapSpace)) { point in
                    // Toque no mapa: move o pin para lá.
                    if let c = proxy.convert(point, from: .named(mapSpace)) {
                        withAnimation(.snappy) { pin = c }
                        haptic(.light)
                    }
                }

                let _ = cameraTick
                if let tip = proxy.convert(pin, to: .named(mapSpace)) {
                    DraggablePin(isDragging: isDragging)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(mapSpace))
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        grabOffset = CGSize(width: tip.x - value.startLocation.x,
                                                            height: tip.y - value.startLocation.y)
                                        haptic(.medium)
                                    }
                                    let target = CGPoint(x: value.location.x + grabOffset.width,
                                                         y: value.location.y + grabOffset.height)
                                    if let c = proxy.convert(target, from: .named(mapSpace)) {
                                        pin = c
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    haptic(.light)
                                }
                        )
                        // A ponta do pin fica exatamente sobre a coordenada.
                        .position(x: tip.x, y: tip.y - DraggablePin.height / 2)
                }
            }
            .coordinateSpace(.named(mapSpace))
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
        if let mapCenter {
            request.region = MKCoordinateRegion(center: mapCenter, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return show("Nada encontrado") }
            let c = item.placemark.coordinate
            pin = c
            withAnimation {
                position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200))
            }
        } catch {
            show("Nada encontrado")
        }
    }

    // MARK: - Painel inferior

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ponto escolhido").font(.caption).foregroundStyle(.secondary)
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
                    if let mapCenter { withAnimation(.snappy) { pin = mapCenter } }
                } label: {
                    Image(systemName: "scope")
                }
                .padding(.leading, 10)
                .accessibilityLabel("Trazer pin para o centro do mapa")
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

struct DraggablePin: View {
    static let height: CGFloat = 52
    var isDragging: Bool

    var body: some View {
        VStack(spacing: -7) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(.systemBackground), Color(.label))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(.label))
        }
        .frame(width: 48, height: Self.height, alignment: .bottom)
        .shadow(color: .black.opacity(0.3), radius: isDragging ? 8 : 3, y: isDragging ? 6 : 2)
        .scaleEffect(isDragging ? 1.2 : 1, anchor: .bottom)
        .animation(.snappy(duration: 0.15), value: isDragging)
        .contentShape(Rectangle())
        .accessibilityLabel("Pin arrastável")
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
