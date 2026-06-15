import java.io.*;
public class CleanTryWithResources {
    String first(String path) throws IOException {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {  // correct: try-with-resources closes
            return r.readLine();
        }
    }
}
