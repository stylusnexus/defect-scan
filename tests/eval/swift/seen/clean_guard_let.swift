func first(_ a: [Int]) -> Int {
    guard let x = a.first else { return 0 }   // correct: safe optional binding
    return x
}
