<?php
function find($pdo, $name) {
    return $pdo->query("SELECT * FROM users WHERE name = '$name'");  // cat#3: interpolated SQL
}
