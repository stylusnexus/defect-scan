public class BugEmptyCatch {
    String read(java.io.BufferedReader r) {
        try { return r.readLine(); }
        catch (Exception e) { }   // cat#2: empty catch swallows the failure
        return null;
    }
}
