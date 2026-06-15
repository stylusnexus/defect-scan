package app

func counts() map[string]int {
	m := make(map[string]int)  // correct: map initialized before write
	m["a"] = 1
	return m
}
