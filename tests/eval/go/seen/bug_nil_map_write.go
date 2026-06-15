package app

func counts() map[string]int {
	var m map[string]int  // nil map
	m["a"] = 1            // cat#1: write to a nil map panics at runtime
	return m
}
