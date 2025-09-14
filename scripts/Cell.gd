class_name Cell
extends Resource

# Constants based on original xbattle
const MAX_PLAYERS = 11
const MAX_DIRECTIONS = 6
const MAX_MAXVAL: int = 50 # max troops per cell
const TOWN_MIN: int = 50
const TOWN_MAX: int = 100

const DEFAULT_BOARD: int = 15
const DEFAULT_CELL_SIZE: int = 64
const DEFAULT_MAXVAL: int = 20
const DEFAULT_FIGHT: int = 5 # combat intensity
const DEFAULT_MOVE: int = 3 # movement speed
const MOVE_PENALTY = 0.2

const SIDE_NONE: int = -1
const SIDE_FIGHT: int = 11
const HORIZON: int = 2

@export var x: int = 0
@export var y: int = 0
@export var index: int = 0

# Ownership and troops
@export var side: int = SIDE_NONE
@export var troop_values: Array[int] = []  # Troops per side [0-maxval]
@export var old_side: int = SIDE_NONE

# Terrain
@export var level: int = Board.FLAT_LAND  # Terrain elevation (-sea to +hills)
@export var growth: int = 0  # Town production rate (0-255)

# Movement
@export var move: int = 0  # Number of active direction vectors
@export var direction_vectors: Array[bool] = []  # [0-6 directions]
@export var age: int = 0  # How long owned by same side

# Combat state
@export var lowbound: int = 0  # Reserve troops (can't move)

# Visibility and updates
@export var outdated: bool = false
@export var seen_by: Array[bool] = []  # Visibility per side

# Special operations
@export var manage_update: int = 0  # Managed operation type
@export var manage_dir: int = -1  # Direction for managed ops

# Connections to adjacent cells
var connections: Array[Cell] = []

func _init():
    # Initialize arrays
    troop_values.resize(MAX_PLAYERS)
    troop_values.fill(0)
    direction_vectors.resize(MAX_DIRECTIONS)
    direction_vectors.fill(false)
    seen_by.resize(MAX_PLAYERS)
    seen_by.fill(false)
    connections.resize(MAX_DIRECTIONS)

# Get total troops for the owning side
func get_troop_count() -> int:
    if side < 0 or side >= MAX_PLAYERS:
        return 0
    return troop_values[side]

# Set troops for a specific side
func set_troops(new_side: int, count: int):
    if new_side >= 0 and new_side < MAX_PLAYERS:
        troop_values[new_side] = count
        if count > 0 and side == SIDE_NONE:
            side = new_side

# Add troops to current owner
func add_troops(count: int):
    if side >= 0 and side < MAX_PLAYERS:
        troop_values[side] = min(troop_values[side] + count, get_max_capacity())

# Get maximum troop capacity for this cell
func get_max_capacity() -> int:
    # Default maxval from original, could be made configurable
    return MAX_MAXVAL

# Check if cell is fighting (multiple sides present)
func is_fighting() -> bool:
    return side == SIDE_FIGHT

# Check if cell is empty
func is_empty() -> bool:
    return side == SIDE_NONE

# Check if cell can produce troops (has a town)
func can_produce_troops() -> bool:
    return growth > 0

# Get movement speed modifier based on terrain
func get_movement_modifier() -> float:
    # Hills slow movement, sea blocks it
    if level <= Board.SHALLOW_SEA:
        return 0.0
    else:
        return 1.0 - (level * MOVE_PENALTY)

# Check if this cell is a town
func is_town() -> bool:
    return growth >= TOWN_MIN

# Get direction vector count
func get_active_directions() -> int:
    var count = 0
    for i in direction_vectors.size():
        if direction_vectors[i]:
            count += 1
    return count

# Set direction vector
func set_direction(dir: int, active: bool):
    if dir >= 0 and dir < MAX_DIRECTIONS:
        var was_active = direction_vectors[dir]
        direction_vectors[dir] = active
        
        # Update move counter
        if active and not was_active:
            move += 1
        elif not active and was_active:
            move = max(0, move - 1)

# Clear all direction vectors
func clear_directions():
    direction_vectors.fill(false)
    move = 0

# Calculate hex distance between this cell and another
func get_distance(other_cell: Cell) -> int:
    # Hex distance formula for offset coordinates
    var dx = abs(x - other_cell.x)
    var dy = abs(y - other_cell.y)
    
    # Adjust for hex grid offset
    if (x % 2) != (other_cell.x % 2):
        if y > other_cell.y:
            dy += 1
    
    return max(dx, dy, dx + dy - max(dx, dy))

# Check if visible to specific player
func is_seen_by(player: int) -> bool:
    if player < 0 or player >= MAX_PLAYERS:
        return false

    return seen_by[player]

# Get string representation for debugging
func _to_string() -> String:
    return "Cell(%d,%d) side=%d troops=%d level=%d" % [x, y, side, get_troop_count(), level]
