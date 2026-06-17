public class CleanReportedParse {
    int port(String s) {
        return Integer.parseInt(s);   // NumberFormatException propagates to caller; nothing swallowed
    }
}
