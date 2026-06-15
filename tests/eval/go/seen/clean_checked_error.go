package app

import "os"

func writeConfig(path string, data []byte) error {
	if err := os.WriteFile(path, data, 0o644); err != nil {  // correct: error checked + returned
		return err
	}
	return nil
}
