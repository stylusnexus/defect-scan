def load(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:                 # correct: catches a specific, expected error
        return None
