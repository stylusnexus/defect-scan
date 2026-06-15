import kotlinx.coroutines.*
fun fire() {
    GlobalScope.launch { work() }   // cat#5: GlobalScope -> unstructured coroutine leak
}
