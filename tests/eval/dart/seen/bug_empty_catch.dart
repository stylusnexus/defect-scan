Future<String?> load(Uri u) async {
  try { return (await fetch(u)).body; }
  catch (_) { return null; }   // cat#2: swallows the error, caller never learns
}
