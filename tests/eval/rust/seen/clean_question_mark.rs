use std::collections::HashMap;
fn lookup(m: &HashMap<String, i32>, k: &str) -> Option<i32> {
    Some(*m.get(k)?)   // correct: propagate None via ?, no panic
}
