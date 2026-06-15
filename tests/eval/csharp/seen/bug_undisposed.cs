public class Reader {
    public string First(string path) {
        var r = new System.IO.StreamReader(path);  // cat#4: never disposed (no using)
        return r.ReadLine();
    }
}
