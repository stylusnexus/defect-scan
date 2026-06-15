public class C {
  public string Read(string p) {
    try { return System.IO.File.ReadAllText(p); }
    catch { return null; }
  }
}
