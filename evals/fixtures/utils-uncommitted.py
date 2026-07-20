def divide(numerator, denominator):
    if denominator == 0:
        raise ValueError("denominator must not be zero")
    return numerator / denominator


def clamp(value, lo, hi):
    # TODO: constrain value to the inclusive range [lo, hi].
    pass
