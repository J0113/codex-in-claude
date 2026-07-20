USERS = {"alice": "correct horse battery staple"}


def check_password(username, password):
    expected = USERS.get(username)
    return expected is not None and password == expected


def login(username, password):
    return check_password(username, password)
