def load(path):
    try:
        f = open(path)          # cat#4: never closed
        return f.read()
    except:                     # cat#2: bare except swallows everything
        pass                    # ruff: E722 (bare-except), tool-confirmable
