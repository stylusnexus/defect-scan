def read_first_line(path):
    with open(path) as f:          # correct: context manager closes the file
        return f.readline().strip()
