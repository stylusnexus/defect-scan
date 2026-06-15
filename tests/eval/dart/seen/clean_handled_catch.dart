Future<String?> load(Uri u) async {
  try { return (await fetch(u)).body; }
  catch (e) { log(e); rethrow; }   // correct: logs and rethrows
}
