<?php
function load($path) {
    $data = file_get_contents($path);
    if ($data === false) { throw new RuntimeException("read failed: $path"); }  // correct: checked, not suppressed
    return strlen($data);
}
