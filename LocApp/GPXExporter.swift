import CoreLocation
import Foundation

/// Gera arquivos .gpx que o Xcode aceita em "Simulate Location".
enum GPXExporter {
    static func gpxString(for coordinate: CLLocationCoordinate2D, name: String = "LocApp") -> String {
        // String(format:) sem locale usa ponto decimal, que é o que o GPX exige.
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        let time = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LocApp" xmlns="http://www.topografix.com/GPX/1/1">
            <wpt lat="\(lat)" lon="\(lon)">
                <name>\(escape(name))</name>
                <time>\(time)</time>
            </wpt>
        </gpx>

        """
    }

    /// Escreve o .gpx num arquivo temporário e devolve a URL (para compartilhar/AirDrop).
    static func writeFile(for coordinate: CLLocationCoordinate2D) throws -> URL {
        let fileName = String(format: "Local_%.5f_%.5f.gpx", coordinate.latitude, coordinate.longitude)
            .replacingOccurrences(of: "-", with: "m")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let name = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        try gpxString(for: coordinate, name: name).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
