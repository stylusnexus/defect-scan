fun greet(name: String?): Int {
    return name!!.length   // cat#1: !! on a nullable -> NPE if name is null
}
