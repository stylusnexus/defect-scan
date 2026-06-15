def append_item(item, bucket=[]):  # cat#5/python: mutable default arg shared across calls
    bucket.append(item)
    return bucket
