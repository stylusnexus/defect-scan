class C {
    var handler: (() -> Void)?
    func setup() {
        handler = { self.work() }   // cat#4: escaping closure captures strong self -> retain cycle
    }
}
