fn query(conn: &Conn, name: &str) -> Result<Rows, Error> {
    conn.execute_params("SELECT * FROM users WHERE name = ?", &[name])  // correct: parameterized
}
