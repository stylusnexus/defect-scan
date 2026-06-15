<?php
function load($path) {
    $data = @file_get_contents($path);  // cat#2: @ suppresses the failure; $data is silently false
    return strlen($data);
}
