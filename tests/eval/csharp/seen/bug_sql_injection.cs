using System.Data.SqlClient;
public class Repo {
    public void Find(SqlConnection c, string q) {
        var cmd = new SqlCommand("SELECT * FROM users WHERE name = '" + q + "'", c);  // cat#3: concatenated SQL
        cmd.ExecuteReader();
    }
}
