import Foundation
func parse(_ d: Data) -> Any? {
    do { return try JSONSerialization.jsonObject(with: d) }
    catch { return nil }   // handled (could log) — not a force-try crash
}
