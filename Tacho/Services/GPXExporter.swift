import Foundation

enum GPXExporter {
    static func gpx(name: String, points: [TrackPoint]) -> String {
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Tacho" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(escape(name))</name>
            <trkseg>

        """
        for p in points {
            s += "      <trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(String(format: "%.1f", p.alt))</ele><time>\(iso.string(from: p.t))</time><extensions><speed>\(String(format: "%.2f", p.speed))</speed></extensions></trkpt>\n"
        }
        s += """
            </trkseg>
          </trk>
        </gpx>
        """
        return s
    }

    static func write(trip: Trip, points: [TrackPoint]) -> URL? {
        let safe = trip.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Tacho" : safe).gpx")
        do {
            try gpx(name: trip.name, points: points).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
