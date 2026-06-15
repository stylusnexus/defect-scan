using System.Data.SqlClient;
public class Repo {
    public void Find(SqlConnection c, string q) {
        var cmd = new SqlCommand("SELECT * FROM users WHERE name = @n", c);  // correct: parameterized
        cmd.Parameters.AddWithValue("@n", q);
        cmd.ExecuteReader();
    }
}
