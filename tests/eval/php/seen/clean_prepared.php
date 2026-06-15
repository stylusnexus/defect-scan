<?php
function find($pdo, $name) {
    $stmt = $pdo->prepare("SELECT * FROM users WHERE name = ?");  // correct: prepared + bound
    $stmt->execute([$name]);
    return $stmt;
}
