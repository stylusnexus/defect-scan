fn first(v: &[i32]) -> i32 {
    v[0]   // cat#1: panic-prone indexing; use v.get(0)
}
