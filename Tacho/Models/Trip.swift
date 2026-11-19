import Foundation
import SwiftData
import CoreLocation

/// Ein einzelner aufgezeichneter GPS-Punkt.
struct TrackPoint: Codable, Hashable, Identifiable {
    var t: Date
    var lat: Double
    var lon: Double
    var alt: Double
    var speed: Double        // m/s
    var accuracy: Double     // m
    var activity: ActivityType

    var id: Date { t }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

struct ActivityShare: Identifiable {
    var activity: ActivityType
    var share: Double
    var id: String { activity.rawValue }
}

@Model
final class Trip {
    var name: String
    var startDate: Date
    var endDate: Date
    var distance: Double          // m
    var movingTime: TimeInterval  // s
    var maxSpeed: Double          // m/s
    var elevationGain: Double     // m
    var elevationLoss: Double     // m
    var activityRaw: String
    var startPlace: String?
    var endPlace: String?
    var note: String?
    @Attribute(.externalStorage) var pointsData: Data

    init(name: String,
         startDate: Date,
         endDate: Date,
         distance: Double,
         movingTime: TimeInterval,
         maxSpeed: Double,
         elevationGain: Double,
         elevationLoss: Double,
         activity: ActivityType,
         points: [TrackPoint]) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.movingTime = movingTime
        self.maxSpeed = maxSpeed
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.activityRaw = activity.rawValue
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
    }

    var activity: ActivityType {
        get { ActivityType(rawValue: activityRaw) ?? .unknown }
        set { activityRaw = newValue.rawValue }
    }

    var points: [TrackPoint] {
        (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? []
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var averageSpeed: Double { movingTime > 0 ? distance / movingTime : 0 }

    /// Anteil je Fortbewegungsart (Zeit-basiert).
    func activityBreakdown(from pts: [TrackPoint]) -> [ActivityShare] {
        guard pts.count > 1 else { return [ActivityShare(activity: activity, share: 1)] }
        var acc: [ActivityType: Double] = [:]
        for i in 1..<pts.count {
            let dt = pts[i].t.timeIntervalSince(pts[i - 1].t)
            acc[pts[i].activity, default: 0] += min(dt, 30)
        }
        let total = acc.values.reduce(0, +)
        guard total > 0 else { return [ActivityShare(activity: activity, share: 1)] }
        return acc.map { ActivityShare(activity: $0.key, share: $0.value / total) }.sorted { $0.share > $1.share }
    }
}

@Model
final class SprintResult {
    var date: Date
    var targetKmh: Double
    var time: TimeInterval
    var distance: Double
    var activityRaw: String

    init(date: Date, targetKmh: Double, time: TimeInterval, distance: Double, activity: ActivityType) {
        self.date = date
        self.targetKmh = targetKmh
        self.time = time
        self.distance = distance
        self.activityRaw = activity.rawValue
    }

    var activity: ActivityType { ActivityType(rawValue: activityRaw) ?? .unknown }
}
