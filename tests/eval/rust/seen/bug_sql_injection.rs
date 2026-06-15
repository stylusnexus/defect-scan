fn query(conn: &Conn, name: &str) -> Result<Rows, Error> {
    let sql = format!("SELECT * FROM users WHERE name = '{}'", name);  // cat#3: format!-built SQL
    conn.execute(&sql)
}
