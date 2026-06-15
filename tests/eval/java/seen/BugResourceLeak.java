import java.io.*;
public class BugResourceLeak {
    String first(String path) throws IOException {
        BufferedReader r = new BufferedReader(new FileReader(path));  // cat#4: never closed (no try-with-resources)
        return r.readLine();
    }
}
