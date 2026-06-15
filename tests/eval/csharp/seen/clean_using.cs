public class Reader {
    public string First(string path) {
        using var r = new System.IO.StreamReader(path);  // correct: using disposes the reader
        return r.ReadLine();
    }
}
