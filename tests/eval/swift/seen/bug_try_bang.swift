import Foundation
func parse(_ d: Data) -> Any {
    return try! JSONSerialization.jsonObject(with: d)   // cat#1: try! traps on a thrown error
}
