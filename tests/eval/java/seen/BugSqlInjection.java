import java.sql.*;
public class BugSqlInjection {
    void find(Connection c, String name) throws SQLException {
        Statement st = c.createStatement();
        st.executeQuery("SELECT * FROM users WHERE name = '" + name + "'");  // cat#3: concatenated SQL
    }
}
