fun load(path: String): String? {
    return try { java.io.File(path).readText() }
    catch (e: Exception) { null }   // cat#2: swallowed exception, caller never learns
}
