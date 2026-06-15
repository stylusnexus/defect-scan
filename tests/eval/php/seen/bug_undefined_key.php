<?php
function name($req) {
    return strtoupper($req['name']);  // cat#1: undefined array key if 'name' absent -> warning + null
}
