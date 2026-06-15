import kotlinx.coroutines.*
suspend fun fire() = coroutineScope {   // correct: structured concurrency, scoped to caller
    launch { work() }
}
