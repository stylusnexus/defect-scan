<?php
function f($pdo, $id) {
  return $pdo->query("SELECT * FROM t WHERE id = $id");
}
