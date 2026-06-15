public class CleanLoggedRethrow {
    String read(java.io.BufferedReader r) throws java.io.IOException {
        try { return r.readLine(); }
        catch (java.io.IOException e) {   // NEAR-MISS: looks like a swallow, but logs and rethrows
            System.err.println(e);
            throw e;
        }
    }
}
