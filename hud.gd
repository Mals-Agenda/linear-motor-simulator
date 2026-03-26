func _state_colour(state):
    match state:
        "idle":
            return Color(1, 1, 1)
        "running":
            return Color(0, 1, 0)
        "paused":
            return Color(1, 1, 0)
        "error":
            return Color(1, 0, 0)
        _:
            return Color(1, 1, 1)  # default color
