class_name Board
extends Resource

# Board configuration
@export var width: int = 15
@export var height: int = 15
@export var cell_size: int = 32

# Cell storage
var cells: Array[Array] = []  # 2D array of Cell objects
var cell_list: Array[Cell] = []  # 1D list for iteration

# Hexagonal directions (always hex tiles)
const HEX_DIRECTIONS = [
    Vector2i(0, -1),   # UP
    Vector2i(-1, 0),   # LEFT_UP
    Vector2i(-1, 1),   # LEFT_DOWN
    Vector2i(0, 1),    # DOWN
    Vector2i(1, 1),    # RIGHT_DOWN
    Vector2i(1, 0)     # RIGHT_UP
]

func _init(board_width: int = 15, board_height: int = 15):
    width = board_width
    height = board_height
    generate_board()

# Generate the complete board
func generate_board():
    cells.clear()
    cell_list.clear()
    
    # Create 2D array structure
    cells.resize(width)
    for x in width:
        cells[x] = []
        cells[x].resize(height)
        
        for y in height:
            var cell = Cell.new()
            cell.x = x
            cell.y = y
            cell.index = y * width + x
            cells[x][y] = cell
            cell_list.append(cell)
    
    # Set up connections between cells
    setup_connections()
    
    print("Generated %dx%d board with %d cells" % [width, height, cell_list.size()])

# Set up connections between adjacent cells
func setup_connections():
    for x in width:
        for y in height:
            var cell = cells[x][y]
            setup_cell_connections(cell)

func setup_cell_connections(cell: Cell):
    for i in HEX_DIRECTIONS.size():
        var dir = HEX_DIRECTIONS[i]
        var neighbor_pos = Vector2i(cell.x, cell.y) + dir
        
        # Handle wrapping or edge cases
        neighbor_pos = wrap_position(neighbor_pos)
        
        if is_valid_position(neighbor_pos):
            var neighbor = cells[neighbor_pos.x][neighbor_pos.y]
            cell.connections[i] = neighbor
        else:
            cell.connections[i] = null  # Edge of board

func wrap_position(pos: Vector2i) -> Vector2i:
    # Handle board wrapping (optional feature)
    # For now, no wrapping
    return pos

func is_valid_position(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

# Get cell at position
func get_cell(x: int, y: int) -> Cell:
    if is_valid_position(Vector2i(x, y)):
        return cells[x][y]
    return null

# Get cell by index
func get_cell_by_index(index: int) -> Cell:
    if index >= 0 and index < cell_list.size():
        return cell_list[index]
    return null

# Generate random terrain (hills, sea, forest)
func generate_terrain(hill_density: int = 0, sea_density: int = 0, forest_density: int = 0):
    var noise = FastNoiseLite.new()
    noise.seed = randi()
    noise.frequency = 0.1
    
    for cell in cell_list:
        var noise_value = noise.get_noise_2d(cell.x, cell.y)
        
        if noise_value > 0.3:
            cell.level = 1 + int((noise_value - 0.3) * 10)  # Hills
        elif noise_value < -0.4:
            cell.level = -1 - int(abs(noise_value + 0.4) * 5)  # Sea
        else:
            cell.level = 0  # Flat

# Place towns randomly
func place_random_towns(town_density: int):
    for cell in cell_list:
        if cell.level <= 1 and town_density > 0 and randi() % 100 < town_density:
            cell.growth = 50 + randi() % 51

# Place player bases
func place_player_bases(player_count: int, base_count_per_player: int = 1):
    print("Placing %d bases for %d players" % [base_count_per_player, player_count])
    
    var placed_bases = 0
    var attempts = 0
    var max_attempts = 1000
    
    for player in player_count:
        for base_num in base_count_per_player:
            attempts = 0
            while attempts < max_attempts:
                var cell = cell_list[randi() % cell_list.size()]
                
                # Check if suitable for base (not sea, not too close to other bases)
                if cell.level >= 0 and cell.side == Cell.SIDE_NONE and is_good_base_location(cell, player):
                    cell.side = player
                    cell.set_troops(player, 20)  # Starting troops
                    cell.growth = 75  # Base production
                    placed_bases += 1
                    print("Placed base for player %d at (%d,%d)" % [player, cell.x, cell.y])
                    break
                
                attempts += 1
            
            if attempts >= max_attempts:
                print("Warning: Could not place base for player %d" % player)

func is_good_base_location(cell: Cell, player: int) -> bool:
    # Check minimum distance from other player bases
    var min_distance = 3
    
    for other_cell in cell_list:
        if other_cell.side >= 0 and other_cell.side != player:
            var distance = abs(other_cell.x - cell.x) + abs(other_cell.y - cell.y)
            if distance < min_distance:
                return false
    
    return true

# Get neighbors of a cell
func get_neighbors(cell: Cell) -> Array[Cell]:
    var neighbors: Array[Cell] = []
    for connection in cell.connections:
        if connection != null:
            neighbors.append(connection)
    return neighbors

# Get all cells owned by a specific side
func get_cells_for_side(side: int) -> Array[Cell]:
    var side_cells: Array[Cell] = []
    for cell in cell_list:
        if cell.side == side:
            side_cells.append(cell)
    return side_cells

# Check victory conditions
func check_victory() -> int:
    var active_sides = {}
    
    for cell in cell_list:
        if cell.side >= 0 and cell.side < Cell.MAX_SIDES and cell.get_troop_count() > 0:
            active_sides[cell.side] = true
    
    var active_count = active_sides.size()
    if active_count == 1:
        return active_sides.keys()[0]  # Winner
    elif active_count == 0:
        return -2  # Draw (everyone died)
    else:
        return -1  # Game continues

# Get board statistics
func get_stats() -> Dictionary:
    var stats = {
        "total_cells": cell_list.size(),
        "occupied_cells": 0,
        "fighting_cells": 0,
        "towns": 0,
        "sides": {}
    }
    
    for cell in cell_list:
        if cell.side >= 0:
            stats.occupied_cells += 1
            if cell.is_fighting():
                stats.fighting_cells += 1
            
            if not stats.sides.has(cell.side):
                stats.sides[cell.side] = {"cells": 0, "troops": 0}
            stats.sides[cell.side].cells += 1
            stats.sides[cell.side].troops += cell.get_troop_count()
        
        if cell.is_town():
            stats.towns += 1
    
    return stats

func _to_string() -> String:
    return "Board %dx%d (hex) with %d cells" % [width, height, cell_list.size()]
