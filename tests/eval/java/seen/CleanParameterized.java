import java.sql.*;
public class CleanParameterized {
    void find(Connection c, String name) throws SQLException {
        PreparedStatement st = c.prepareStatement("SELECT * FROM users WHERE name = ?");  // correct: parameterized
        st.setString(1, name);
        st.executeQuery();
    }
}
