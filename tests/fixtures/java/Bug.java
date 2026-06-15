public class Bug {
  String read(java.io.BufferedReader r) {
    try { return r.readLine(); }
    catch (Exception e) { return null; }
  }
}
