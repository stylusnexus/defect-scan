def read_first_line(path):
    f = open(path)  # cat#4: file opened without `with`; never closed on the return path
    line = f.readline()
    return line.strip()
