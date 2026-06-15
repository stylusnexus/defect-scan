use std::collections::HashMap;
fn lookup(m: &HashMap<String, i32>, k: &str) -> i32 {
    *m.get(k).unwrap()   // panic: unwrap on a recoverable None — panics in prod instead of returning Result/Option
}
