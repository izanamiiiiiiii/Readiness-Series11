import Foundation

public enum NightQuality {
    public static func trustedSource(product: String, bundle: String, manual: Bool) -> Bool {
        product.lowercased().hasPrefix("watch") && bundle.hasPrefix("com.apple.health.") && !manual
    }
    // Local noon-to-noon window. Split at the boundary rather than assigning stages independently.
    public static func nights(_ intervals: [DateInterval], calendar: Calendar) -> [Date: [DateInterval]] {
        var groups: [Date: [DateInterval]] = [:]
        for interval in intervals where interval.duration > 0 {
            var cursor = interval.start
            while cursor < interval.end {
                let day = calendar.startOfDay(for: cursor)
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
                let morning = cursor < noon ? day : calendar.date(byAdding: .day, value: 1, to: day)!
                let boundary = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning)!
                let end = min(boundary, interval.end)
                groups[morning, default: []].append(DateInterval(start: cursor, end: end))
                cursor = end
            }
        }
        return groups.mapValues { segments in
            var merged: [DateInterval] = []
            for segment in segments.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, segment.start <= last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, segment.end))
                } else { merged.append(segment) }
            }
            return merged
        }
    }
    public static func contains(start: Date, end: Date, segments: [DateInterval]) -> Bool {
        end > start && segments.contains { start >= $0.start && end <= $0.end }
    }
}
