extends Control

# Assuming this is the correct structure for the hud.gd file

# Other code here...

# Function that sets the state color
func _state_colour(state):
    match state:
        "armed":
            # set color for armed state
            pass
        "disarmed":
            # set color for disarmed state
            pass
        _:
            # default color
            pass

# Other code here...

# Update to correct line 233
_btn_arm.disabled = false
