public class Loader {
    public string Read(string path) {
        try { return System.IO.File.ReadAllText(path); }
        catch { return null; }   // cat#2: empty catch swallows the failure
    }
}
