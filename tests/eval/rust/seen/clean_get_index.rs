fn first(v: &[i32]) -> Option<i32> {
    v.get(0).copied()   // NEAR-MISS: looks like the indexing bug, but .get returns Option (no panic)
}
