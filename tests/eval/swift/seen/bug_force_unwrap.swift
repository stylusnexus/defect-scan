func first(_ a: [Int]) -> Int {
    return a.first!   // cat#1: force-unwrap crashes on an empty array
}
