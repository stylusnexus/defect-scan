import java.io.*;
import java.nio.file.*;
public class CleanSafePath {
    byte[] load(String name) throws IOException {
        if (!name.matches("[a-z0-9]+")) throw new IllegalArgumentException("bad name");  // strict whitelist
        return Files.readAllBytes(Paths.get("/data").resolve(name));   // no separators possible -> no traversal
    }
}
