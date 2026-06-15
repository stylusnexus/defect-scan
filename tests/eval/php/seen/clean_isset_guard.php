<?php
function name($req) {
    // NEAR-MISS: looks like the undefined-key bug, but guards with ?? before use
    return strtoupper($req['name'] ?? '');
}
