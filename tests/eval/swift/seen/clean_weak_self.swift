class C {
    var handler: (() -> Void)?
    func setup() {
        handler = { [weak self] in self?.work() }   // NEAR-MISS: looks like the cycle, but [weak self] breaks it
    }
}
