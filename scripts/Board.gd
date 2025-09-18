class_name Board
extends Control

# constants
const player_colors = [
    Color.RED,      # Player 0
    Color.BLUE,     # Player 1  
    Color.GREEN,    # Player 2
    Color.YELLOW,   # Player 3
    Color.MAGENTA,  # Player 4
    Color.CYAN,     # Player 5
    Color.ORANGE,   # Player 6
    Color.PURPLE,   # Player 7
    Color.BROWN,    # Player 8
    Color.PINK,     # Player 9
    Color.GRAY      # Player 10
]

const DEEP_SEA = -2
const SHALLOW_SEA = -1
const FLAT_LAND = 0
const FOREST = 1
const LOW_HILLS = 2
const HIGH_HILLS = 3
const FOG = "FOG"

const COLOURS = {
    DEEP_SEA: Color.CORNFLOWER_BLUE,
    SHALLOW_SEA: Color.LIGHT_BLUE,
    FLAT_LAND: Color(0.8, 0.8, 0.4),
    FOREST: Color.SEA_GREEN,
    LOW_HILLS: Color.SADDLE_BROWN,
    HIGH_HILLS: Color.LIGHT_GRAY,
    FOG: Color(0.1, 0.1, 0.1),
}

# Board configuration
@export var width: int = 15
@export var height: int = 15
@export var border_width: int = 1
@export var show_direction_vectors: bool = true
@export var show_troop_numbers: bool = false
@export var cell_list: Array[Cell] = []  # 1D list for iteration

# Cell storage
var cell_height: int = Cell.DEFAULT_CELL_SIZE
var cell_width = 2 * cell_height / sqrt(3)
var cells: Array[Array] = []  # 2D array of Cell objects

# Game reference
var game_manager: GameManager

# UI state
var selected_cell: Cell = null
var mouse_down: bool = false
var hovered_cell: Cell = null
var offset_x: float = 0.0

func _init(board_width: int = 15, board_height: int = 15):
    width = board_width
    height = board_height
    mouse_filter = Control.MOUSE_FILTER_STOP
    generate_board()
    
func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    gui_input.connect(_on_gui_input)
    setup_initial_window()
    get_viewport().size_changed.connect(_on_viewport_resized)
    set_process_input(true)

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            show_troop_numbers = !show_troop_numbers
            queue_redraw()
        elif hovered_cell:
            var command = key_to_command(event.keycode)
            if command >= 0:
                if selected_cell == null:
                    selected_cell = hovered_cell
                game_manager.on_cell_command(command, hovered_cell, selected_cell)

func key_to_command(keycode: int) -> int:
   match keycode:
       KEY_A: return NetworkManager.CMD_ATTACK
       KEY_D: return NetworkManager.CMD_DIG
       KEY_F: return NetworkManager.CMD_FILL
       KEY_B: return NetworkManager.CMD_BUILD
       KEY_S: return NetworkManager.CMD_SCUTTLE
       KEY_P: return NetworkManager.CMD_PARATROOPS
       KEY_R: return NetworkManager.CMD_ARTILLERY
       _: return -1

func _on_viewport_resized():
    var viewport = get_viewport().get_visible_rect().size
    calculate_scaling(viewport.x, viewport.y)
    queue_redraw()

func get_hex_directions(x: int) -> Array[Vector2i]:
    if x % 2 == 0:  # Even column
        return [
            Vector2i(0, -1),   # UP
            Vector2i(-1, -1),  # LEFT_UP
            Vector2i(-1, 0),   # LEFT_DOWN
            Vector2i(0, 1),    # DOWN
            Vector2i(1, 0),    # RIGHT_DOWN
            Vector2i(1, -1)    # RIGHT_UP
        ]

    return [
        Vector2i(0, -1),   # UP
        Vector2i(-1, 0),   # LEFT_UP
        Vector2i(-1, 1),   # LEFT_DOWN
        Vector2i(0, 1),    # DOWN
        Vector2i(1, 1),    # RIGHT_DOWN
        Vector2i(1, 0)     # RIGHT_UP
    ]

func get_render_direction(direction_index: int) -> Vector2:
    # Convert logical grid directions to visual directions
    match direction_index:
        0: return Vector2(0, -1)        # UP
        1: return Vector2(-0.866, -0.5) # LEFT_UP
        2: return Vector2(-0.866, 0.5)  # LEFT_DOWN
        3: return Vector2(0, 1)         # DOWN
        4: return Vector2(0.866, 0.5)   # RIGHT_DOWN
        5: return Vector2(0.866, -0.5)  # RIGHT_UP
        _: return Vector2.ZERO

# BOARD GENERATION
func generate_board():
    cells.clear()
    cell_list.clear()
    var idx = 0
    
    cells.resize(width)
    for x in width:
        cells[x] = []
        cells[x].resize(height)
        
        for y in height:
            var cell = Cell.new()
            cell.x = x
            cell.y = y
            cell.index = idx
            cells[x][y] = cell
            cell_list.append(cell)
            idx += 1
    
    setup_connections()
    print("Generated %dx%d board with %d cells" % [width, height, cell_list.size()])

func setup_connections():
    for x in width:
        for y in height:
            var cell = cells[x][y]
            setup_cell_connections(cell)

func setup_cell_connections(cell: Cell):
    var hex = get_hex_directions(cell.x)
    for i in Cell.MAX_DIRECTIONS:
        cell.connections[i] = null
        var neighbor_pos = Vector2i(cell.x, cell.y) + hex[i]
        if is_valid_position(neighbor_pos):
            cell.connections[i] = cells[neighbor_pos.x][neighbor_pos.y]

# COORDINATE SYSTEM
func is_valid_position(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func get_cell(x: int, y: int) -> Cell:
    if is_valid_position(Vector2i(x, y)):
        return cells[x][y]
    return null

func get_cell_by_index(index: int) -> Cell:
    if index >= 0 and index < cell_list.size():
        return cell_list[index]
    return null

func get_cell_at_position(pos: Vector2) -> Cell:
    var adjusted_pos = Vector2(pos.x - offset_x, pos.y)
    var grid_x = int(adjusted_pos.x / (cell_width * 0.75))
    var grid_y = int((adjusted_pos.y - (grid_x % 2) * cell_height * 0.5) / cell_height)
    
    # Check this cell and neighbors
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            var test_x = grid_x + dx
            var test_y = grid_y + dy
            var cell = get_cell(test_x, test_y)
            if cell and point_in_hex(adjusted_pos, cell):
                return cell
    
    return null

func point_in_hex(point: Vector2, cell: Cell) -> bool:
    var x_radius = cell_width / 2
    var y_radius = cell_height / 2
    var x_pos = cell.x * cell_width * 0.75  # No offset_x here
    var y_pos = cell.y * cell_height + (cell.x % 2) * y_radius
    var center = Vector2(x_pos + x_radius, y_pos + y_radius)
    var distance = point.distance_to(center)
    return distance <= cell_width * 0.5

# TERRAIN GENERATION
func generate_terrain(hill_density: float, sea_density: float, forest_density: float):
    var noise = FastNoiseLite.new()
    noise.seed = randi()
    noise.frequency = 0.1
    
    for cell in cell_list:
        var noise_value = noise.get_noise_2d(cell.x, cell.y)
        var rand = randf() * 100.0
        
        # Use noise to bias terrain placement
        if noise_value < -0.4 and rand < sea_density * 2:
            cell.level = SHALLOW_SEA + (randi() % 2) * (DEEP_SEA - SHALLOW_SEA)
        elif noise_value > 0.3 and rand < hill_density * 2:
            cell.level = LOW_HILLS + (randi() % 2)
        elif noise_value > 0.1 and noise_value < 0.3 and rand < forest_density * 2:
            cell.level = FOREST
        else:
            cell.level = FLAT_LAND

func place_random_towns(town_density: int):
    for cell in cell_list:
        if cell.level >= 0 and town_density > 0 and randi() % 100 < town_density:
            cell.growth = 50 + randi() % 51

func place_player_bases(player_count: int, base_count: int = 1) -> Array[Cell]:
    print("Placing %d bases for %d players" % [base_count, player_count])

    var arr: Array[Cell] = []
    for player in player_count:
        for base_num in base_count:
            var attempts = 0
            while attempts < 1000:
                var cell = cell_list[randi() % cell_list.size()]
                
                if cell.level >= 0 and cell.side == Cell.SIDE_NONE and is_good_base_location(cell, player):
                    cell.side = player
                    cell.set_troops(player, 20)
                    cell.growth = 75
                    print("Placed base for player %d at (%d,%d)" % [player, cell.x, cell.y])
                    arr.append(cell)
                    break
                
                attempts += 1

    return arr

func is_good_base_location(cell: Cell, player: int) -> bool:
    var min_distance = 3
    
    for other_cell in cell_list:
        if other_cell.side >= 0 and other_cell.side != player:
            var distance = abs(other_cell.x - cell.x) + abs(other_cell.y - cell.y)
            if distance < min_distance:
                return false
    
    return true

# RENDERING
func setup_initial_window():
    cell_height = Cell.DEFAULT_CELL_SIZE
    cell_width = 2 * Cell.DEFAULT_CELL_SIZE / sqrt(3)
    var board_width = width * cell_width * 3 / 4 + cell_width / 4
    var board_height = height * cell_height + cell_height * 0.5
    print("window is %d x %d with %d x %d cell" % [board_width, board_height, cell_width, cell_height])
    
    get_window().size = Vector2i(int(board_width), int(board_height))

func calculate_scaling(x: int, y: int):
    # Scale to fit height
    var height_scale = y / (height + 1)
    
    # Scale to fit width  
    var board_width = width * 0.75 + 0.25
    var width_scale = x / board_width
    
    # Use smaller scale
    var sm = min(height_scale, width_scale / (2 / sqrt(3)))
    
    cell_height = int(sm)
    cell_width = 2 * cell_height / sqrt(3)
    
    # Center horizontally
    var real_width = width * cell_width * 0.75 + cell_width / 4
    offset_x = (x - real_width) * 0.5

func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
    
    for cell in cell_list:
        draw_cell(cell)

func draw_cell(cell: Cell):
    var my_player = game_manager.current_player
    var hex_points = get_hex_points(cell)
    
    if not cell.is_seen_by(my_player):
        draw_fog(hex_points)
        return
    
    # Terrain
    var terrain_color = get_terrain_color(cell.level)
    draw_colored_polygon(hex_points, terrain_color)
    
    # Border
    if border_width > 0:
        var border_points = hex_points.duplicate()
        border_points.append(hex_points[0])
        draw_polyline(border_points, Color.BLACK, border_width)
    
    # Troops
    if cell.side >= 0:
        var center = get_hex_center(cell)
        if cell.is_fighting():
            draw_fighting_cell(cell, center)
        else:
            draw_owned_cell(cell, center)
    
    # Town indicator
    if cell.is_town():
        draw_town_indicator(cell)
    
    # Direction vectors
    if show_direction_vectors and cell.side >= 0:
        draw_direction_vectors(cell)
    
    # Selection
    if cell == selected_cell:
        var border_points = hex_points.duplicate()
        border_points.append(hex_points[0])
        draw_polyline(border_points, Color.WHITE, 3)

func get_hex_center(cell: Cell) -> Vector2:
    var x_radius = cell_width / 2
    var y_radius = cell_height / 2
    var x_pos = cell.x * cell_width * 0.75 + offset_x
    var y_pos = cell.y * cell_height + (cell.x % 2) * y_radius
    return Vector2(x_pos + x_radius, y_pos + y_radius)

func get_hex_points(cell: Cell) -> PackedVector2Array:
    var points = PackedVector2Array()
    var center = get_hex_center(cell)
    var radius = cell_width / 2
    
    for i in Cell.MAX_DIRECTIONS:
        var angle = PI / 3 * i
        var x = center.x + cos(angle) * radius
        var y = center.y + sin(angle) * radius
        points.append(Vector2(x, y))
    
    return points

func draw_owned_cell(cell: Cell, center: Vector2):
    var player_color = get_player_color(cell.side)
    var troop_count = cell.get_troop_count()
    
    if troop_count > 0:
        var max_radius = cell_height * 0.3
        var radius = max_radius * (float(troop_count) / float(cell.get_max_capacity()))
        radius = max(radius, 4.0)
        
        draw_circle(center, radius, player_color)
        
        if show_troop_numbers and cell.side == game_manager.current_player:
            var font = ThemeDB.fallback_font
            var font_size = max(12, cell_height / 6)
            var text = str(troop_count)
            var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
            var text_pos = center - text_size / 2
            draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func draw_fighting_cell(cell: Cell, center: Vector2):
    var strongest_side = Cell.SIDE_NONE
    var max_troops = 0
    
    # Find side with most troops
    for side in Cell.MAX_PLAYERS:
        if cell.troop_values[side] > max_troops:
            max_troops = cell.troop_values[side]
            strongest_side = side
    
    if strongest_side < 0:
        print("cell is UNDECIDED")
        draw_circle(center, 4.0, Color.GRAY)
        return
    
    # Draw single circle for strongest side
    var max_radius = cell_height * 0.3
    var radius = max_radius * (float(max_troops) / float(cell.get_max_capacity()))
    radius = max(radius, 4.0)
    
    var color = get_player_color(strongest_side)
    draw_circle(center, radius, color, false, 3.0)

    if show_troop_numbers and cell.troop_values[game_manager.current_player] > 0:
        var font = ThemeDB.fallback_font
        var font_size = max(12, cell_height / 6)
        var text = str(cell.troop_values[game_manager.current_player])
        var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
        var text_pos = center - text_size / 2
        draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func draw_town_indicator(cell: Cell):
    var center = get_hex_center(cell)
    var size = Vector2(cell_height * 0.3, cell_height * 0.3)
    var pos = center - size / 2
    var rect = Rect2(pos, size)
    
    draw_rect(rect, Color(1, 1, 1, 0.5))
    draw_rect(rect, Color.BLACK, false, 4)

func draw_direction_vectors(cell: Cell):
    # Only show direction vectors for our own troops
    if cell.side != game_manager.current_player:
        return

    var center = get_hex_center(cell)    
    for i in cell.direction_vectors.size():
        if cell.direction_vectors[i]:
            var dir_vec = get_render_direction(i)
            var end_pos = center + dir_vec * (cell_height * 0.3)
            
            draw_line(center, end_pos, Color.WHITE, 2.0)

# Fog Of War
func draw_fog(hex_points: PackedVector2Array):
    draw_colored_polygon(hex_points, COLOURS[FOG])
    
    if border_width > 0:
        var border_points = hex_points.duplicate()
        border_points.append(hex_points[0])
        draw_polyline(border_points, Color.BLACK, border_width)

func update_fog(player: int, cell: Cell):
    if (player == Cell.SIDE_FIGHT):
        return

    var queue = [{"cell": cell, "distance": 0}]
    var visited = {cell.index: true}
    
    while queue.size() > 0:
        var current = queue.pop_front()
        var check_cell = current.cell
        var dist = current.distance
        
        check_cell.seen_by[player] = true
        
        if dist < Cell.HORIZON:
            for neighbor in get_neighbors(check_cell):
                if not visited.has(neighbor.index):
                    visited[neighbor.index] = true
                    queue.push_back({"cell": neighbor, "distance": dist + 1})

    queue_redraw()

func get_terrain_color(level) -> Color:
    if COLOURS.has(level):
        return COLOURS[level]
    elif level > 3:
        return Color(0.4, 0.5, 0.1)
    else:
        return Color(0.9, 0.9, 0.6)

func get_player_color(side: int) -> Color:
    if side >= 0 and side < player_colors.size():
        return player_colors[side]
    return Color.GRAY

# INPUT HANDLING
func _on_gui_input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                mouse_down = true
                var cell = get_cell_at_position(event.position)
                if cell:
                    selected_cell = cell
                    handle_cell_click(cell, event)
            else:
                mouse_down = false
    
    elif event is InputEventMouseMotion:
        hovered_cell = get_cell_at_position(event.position)
        if mouse_down:
            var cell = hovered_cell
            if cell and cell != selected_cell:
                selected_cell = cell
                queue_redraw()

func handle_cell_click(cell: Cell, event: InputEventMouseButton):
    if not game_manager:
        print("ERROR: no game_manager")
        return
        
    var cell_center = get_hex_center(cell)
    var direction_vec = (event.position - cell_center).normalized()
    
    # Find closest direction using RENDER vectors
    var best_direction = 0
    var best_dot = -2.0
    
    for i in Cell.MAX_DIRECTIONS:
        var render_dir = get_render_direction(i)
        var dot = direction_vec.dot(render_dir)
        if dot > best_dot:
            best_dot = dot
            best_direction = i
    
    var direction_mask = 1 << best_direction
    game_manager.on_cell_click(cell, direction_mask)
    queue_redraw()

# GAME STATE QUERIES
func get_neighbors(cell: Cell) -> Array[Cell]:
    var neighbors: Array[Cell] = []
    for connection in cell.connections:
        if connection != null:
            neighbors.append(connection)
    return neighbors

func get_cells_for_side(side: int) -> Array[Cell]:
    var side_cells: Array[Cell] = []
    for cell in cell_list:
        if cell.side == side:
            side_cells.append(cell)
    return side_cells

func get_active(players: Array) -> Array:
    var active_sides = {}
    
    for cell in cell_list:
        if active_sides.size() == players.size():
            break
            
        if cell.get_troop_count() > 0:
            active_sides[cell.side] = true
        elif cell.side == Cell.SIDE_FIGHT:
            for side in players:
                if cell.troop_values[side] > 0:
                    active_sides[side] = true
    
    return active_sides.keys()

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

# UI CALLBACKS
func on_cell_changed():
    queue_redraw()

func _to_string() -> String:
    return "Board %dx%d (hex) with %d cells" % [width, height, cell_list.size()]
