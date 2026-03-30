@warning_ignore("unused_signal")
extends Node

# Object lifecycle — emitted by GameServer systems, consumed by GameClient systems
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal object_removed(object_id: int, rack: int, slot: int)

# Heat
signal heat_cell_changed(cell_id: int, old_temp: int, new_temp: int)

# Animal state
signal animal_state_changed(animal_id: int, old_state: StringName, new_state: StringName)
signal animal_relocated(animal_id: int, from_x: int, from_y: int, to_x: int, to_y: int)
