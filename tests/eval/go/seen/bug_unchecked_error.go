package app

import "os"

func writeConfig(path string, data []byte) {
	os.WriteFile(path, data, 0o644)  // cat#2: error return ignored — write may silently fail
}
