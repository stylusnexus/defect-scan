def load(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:               # NEAR-MISS: looks like the bare-except bug, but it
        log_error(path)            # re-raises after logging — not a swallowed error.
        raise
