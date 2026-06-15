def load(path):
    try:
        with open(path) as f:
            return f.read()
    except:  # cat#2: bare except swallows everything, incl. KeyboardInterrupt
        return None
