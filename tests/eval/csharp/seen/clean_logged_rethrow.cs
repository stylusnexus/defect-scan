public class Loader {
    public string Read(string path) {
        try { return System.IO.File.ReadAllText(path); }
        catch (System.Exception e) {   // NEAR-MISS: looks like a swallow, but logs and rethrows
            System.Console.Error.WriteLine(e);
            throw;
        }
    }
}
