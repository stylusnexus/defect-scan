public class BugSwallowedParse {
    int port(String s) {
        try { return Integer.parseInt(s); }
        catch (NumberFormatException e) { return 0; }   // swallowed: invalid input silently becomes 0
    }
}
