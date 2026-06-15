package app

import "net/http"

func fetch(url string) (*http.Response, error) {
	resp, err := http.Get(url)  // cat#4: resp.Body never closed (no defer resp.Body.Close())
	if err != nil {
		return nil, err
	}
	return resp, nil
}
