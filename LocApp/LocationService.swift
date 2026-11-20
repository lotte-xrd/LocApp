import CoreLocation
import Combine

/// Fonte única de localização do app.
///
/// O resto do app deve ler `currentLocation` (ou observar `$activeLocation`)
/// em vez de falar direto com o `CLLocationManager`. Assim, quando uma
/// localização simulada é aplicada, todo o app passa a "estar" naquele ponto.
///
/// Importante: isto vale só DENTRO deste app. O iOS não permite que um app
/// comum altere a localização do sistema para outros apps (veja o README).
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    /// Última leitura real do GPS.
    @Published private(set) var realLocation: CLLocation?
    /// Coordenada simulada aplicada pelo usuário (nil = usando GPS real).
    @Published private(set) var simulatedCoordinate: CLLocationCoordinate2D?
    /// Localização que o app deve considerar como "a minha localização".
    @Published private(set) var activeLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    var isSimulating: Bool { simulatedCoordinate != nil }
    var currentLocation: CLLocation? { activeLocation }

    private let manager = CLLocationManager()
    private let defaultsKey = "LocApp.simulatedCoordinate"

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        restoreSavedSimulation()
        recomputeActive()
    }

    // MARK: - Permissão e GPS real

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    // MARK: - Simulação

    /// Fixa `coordinate` como a localização ativa do app.
    func apply(_ coordinate: CLLocationCoordinate2D) {
        simulatedCoordinate = coordinate
        UserDefaults.standard.set(
            ["lat": coordinate.latitude, "lon": coordinate.longitude],
            forKey: defaultsKey
        )
        recomputeActive()
    }

    /// Volta a usar o GPS real.
    func clearSimulation() {
        simulatedCoordinate = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        recomputeActive()
    }

    private func restoreSavedSimulation() {
        guard
            let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
            let lat = dict["lat"] as? Double,
            let lon = dict["lon"] as? Double
        else { return }
        simulatedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func recomputeActive() {
        if let c = simulatedCoordinate {
            activeLocation = CLLocation(
                coordinate: c,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: Date()
            )
        } else {
            activeLocation = realLocation
        }
    }

    fileprivate func handle(locations: [CLLocation]) {
        guard let last = locations.last else { return }
        realLocation = last
        if !isSimulating { recomputeActive() }
    }

    fileprivate func handle(status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handle(locations: locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handle(status: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Erros transitórios (ex.: sem sinal) são ignorados; o GPS tenta de novo sozinho.
    }
}
