import java.io.*;
import java.nio.file.*;
public class BugPathTraversal {
    byte[] load(String name) throws IOException {
        return Files.readAllBytes(Paths.get("/data/" + name));  // untrusted name -> realized path-traversal read
    }
}
