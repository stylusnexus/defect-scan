fun load(path: String): String {
    return try { java.io.File(path).readText() }
    catch (e: Exception) { log(e); throw e }   // NEAR-MISS: looks like a swallow, but rethrows
}
