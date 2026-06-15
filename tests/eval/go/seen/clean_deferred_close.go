package app

import (
	"io"
	"net/http"
)

func fetch(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()  // NEAR-MISS: looks like the leak bug, but defers Close
	return io.ReadAll(resp.Body)
}
