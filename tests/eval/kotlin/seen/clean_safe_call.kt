fun greet(name: String?): Int {
    return name?.length ?: 0   // correct: safe call + default, no NPE
}
