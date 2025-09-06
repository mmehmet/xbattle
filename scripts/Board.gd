class_name Board
extends Control

# Board configuration
@export var width: int = 15
@export var height: int = 15
@export var cell_size: int = 32
@export var border_width: int = 1
@export var show_direction_vectors: bool = true
@export var show_troop_numbers: bool = false

# Cell storage
var cells: Array[Array] = []  # 2D array of Cell objects
var cell_list: Array[Cell] = []  # 1D list for iteration
var col_width: float = 0.0

# Game reference
var game_manager: GameManager

# UI state
var selected_cell: Cell = null
var mouse_down: bool = false

# Colors
const player_colors = [
    Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.MAGENTA,
    Color.CYAN, Color.ORANGE, Color.PURPLE, Color.BROWN, Color.PINK, Color.GRAY
]

const terrain_colors = {
    -2: Color.CORNFLOWER_BLUE,
    -1: Color.LIGHT_BLUE,
    0: Color(0.8, 0.8, 0.4),
    1: Color.DARK_SEA_GREEN,
    2: Color.SEA_GREEN,
    3: Color.DARK_GRAY
}

func _init(board_width: int = 15, board_height: int = 15):
    width = board_width
    height = board_height
    mouse_filter = Control.MOUSE_FILTER_STOP
    generate_board()
    
func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    gui_input.connect(_on_gui_input)
    calculate_scaling()

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
    else:  # Odd column
        return [
            Vector2i(0, -1),   # UP
            Vector2i(-1, 0),   # LEFT_UP
            Vector2i(-1, 1),   # LEFT_DOWN
            Vector2i(0, 1),    # DOWN
            Vector2i(1, 1),    # RIGHT_DOWN
            Vector2i(1, 0)     # RIGHT_UP
        ]

# BOARD GENERATION
func generate_board():
    cells.clear()
    cell_list.clear()
    
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
        var dir = hex[i]
        var neighbor_pos = Vector2i(cell.x, cell.y) + dir
        
        if is_valid_position(neighbor_pos):
            var neighbor = cells[neighbor_pos.x][neighbor_pos.y]
            cell.connections[i] = neighbor
        else:
            cell.connections[i] = null

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
    var cell_x = int(pos.x / col_width)
    var cell_y = int((pos.y - (cell_x % 2) * cell_size * 0.5) / cell_size)
    return get_cell(cell_x, cell_y)

# TERRAIN GENERATION
func generate_terrain(hill_density: int = 0, sea_density: int = 0, forest_density: int = 0):
    var noise = FastNoiseLite.new()
    noise.seed = randi()
    noise.frequency = 0.1
    
    for cell in cell_list:
        var noise_value = noise.get_noise_2d(cell.x, cell.y)
        
        if noise_value > 0.3:
            cell.level = 1 + int((noise_value - 0.3) * 10)
        elif noise_value < -0.4:
            cell.level = -1 - int(abs(noise_value + 0.4) * 5)
        else:
            cell.level = 0

func place_random_towns(town_density: int):
    for cell in cell_list:
        if cell.level <= 1 and town_density > 0 and randi() % 100 < town_density:
            cell.growth = 50 + randi() % 51

func place_player_bases(player_count: int, base_count_per_player: int = 1):
    print("Placing %d bases for %d players" % [base_count_per_player, player_count])
    
    for player in player_count:
        for base_num in base_count_per_player:
            var attempts = 0
            while attempts < 1000:
                var cell = cell_list[randi() % cell_list.size()]
                
                if cell.level >= 0 and cell.side == Cell.SIDE_NONE and is_good_base_location(cell, player):
                    cell.side = player
                    cell.set_troops(player, 20)
                    cell.growth = 75
                    print("Placed base for player %d at (%d,%d)" % [player, cell.x, cell.y])
                    break
                
                attempts += 1

func is_good_base_location(cell: Cell, player: int) -> bool:
    var min_distance = 3
    
    for other_cell in cell_list:
        if other_cell.side >= 0 and other_cell.side != player:
            var distance = abs(other_cell.x - cell.x) + abs(other_cell.y - cell.y)
            if distance < min_distance:
                return false
    
    return true

# RENDERING
func calculate_scaling():
    var viewport_size = get_viewport().get_visible_rect().size
    var wide = viewport_size.x / width
    var tall = viewport_size.y / height
    cell_size = min(wide, tall) * 0.98
    col_width = cell_size * 0.866
    print("Calculated cell_size: %d" % cell_size)

func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
    
    for cell in cell_list:
        draw_cell(cell)

func draw_cell(cell: Cell):
    var hex_points = get_hex_points(cell)
    
    # Terrain
    var terrain_color = get_terrain_color(cell.level)
    draw_colored_polygon(hex_points, terrain_color)
    
    # Border
    if border_width > 0:
        var border_points = hex_points.duplicate()
        border_points.append(hex_points[0])
        draw_polyline(border_points, Color.BLACK, border_width)
    
    # Troops
    if cell.side >= 0 and cell.side < Cell.MAX_SIDES:
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
    var x_pos = cell.x * col_width
    var y_pos = cell.y * cell_size + (cell.x % 2) * cell_size * 0.5
    return Vector2(x_pos + col_width * 0.5, y_pos + cell_size * 0.5)

func get_hex_points(cell: Cell) -> PackedVector2Array:
    var center = get_hex_center(cell)
    var radius = cell_size * 0.55
    var points = PackedVector2Array()
    
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
        var max_radius = cell_size * 0.3
        var radius = max_radius * (float(troop_count) / float(cell.get_max_capacity()))
        radius = max(radius, 3.0)
        
        draw_circle(center, radius, player_color)
        
        if show_troop_numbers and troop_count > 1:
            var font = ThemeDB.fallback_font
            var text = str(troop_count)
            var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
            var text_pos = center - text_size / 2
            draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

func draw_fighting_cell(cell: Cell, center: Vector2):
    var sides_with_troops = []
    for side in Cell.MAX_SIDES:
        if cell.troop_values[side] > 0:
            sides_with_troops.append(side)
    
    if sides_with_troops.size() <= 1:
        return
    
    var segment_angle = 2.0 * PI / sides_with_troops.size()
    
    for i in sides_with_troops.size():
        var side = sides_with_troops[i]
        var color = get_player_color(side)
        var troops = cell.troop_values[side]
        
        var start_angle = i * segment_angle
        var end_angle = (i + 1) * segment_angle
        
        var radius = 12.0 * (float(troops) / 10.0)
        radius = clamp(radius, 4.0, 15.0)
        
        draw_arc(center, radius, start_angle, end_angle, 8, color, 3.0)

func draw_town_indicator(cell: Cell):
    var center = get_hex_center(cell)
    var indicator_size = Vector2(6, 6)
    var indicator_pos = center - indicator_size / 2
    var indicator_rect = Rect2(indicator_pos, indicator_size)
    
    draw_rect(indicator_rect, Color.WHITE)
    draw_rect(indicator_rect, Color.BLACK, false, 1)

func draw_direction_vectors(cell: Cell):
    var center = get_hex_center(cell)
    
    for i in cell.direction_vectors.size():
        if cell.direction_vectors[i]:
            var dir_vec = get_render_direction(i)
            var end_pos = center + dir_vec * (cell_size * 0.3)
            
            draw_line(center, end_pos, Color.WHITE, 2.0)
            draw_arrow_head(end_pos, dir_vec, Color.WHITE)

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

func draw_arrow_head(pos: Vector2, direction: Vector2, color: Color):
    var size = 4.0
    var angle = direction.angle()
    
    var p1 = pos + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * size
    var p2 = pos + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * size
    
    draw_line(pos, p1, color, 2.0)
    draw_line(pos, p2, color, 2.0)

func get_terrain_color(level: int) -> Color:
    if terrain_colors.has(level):
        return terrain_colors[level]
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
    
    elif event is InputEventMouseMotion and mouse_down:
        var cell = get_cell_at_position(event.position)
        if cell and cell != selected_cell:
            selected_cell = cell
            queue_redraw()

func handle_cell_click(cell: Cell, event: InputEventMouseButton):
    if not game_manager:
        print("ERROR: no game_manager")
        return
    
    print("Clicked cell (%d,%d) side=%d troops=%d" % [cell.x, cell.y, cell.side, cell.get_troop_count()])
    
    var cell_center = get_hex_center(cell)
    var direction_vec = (event.position - cell_center).normalized()
    var hex = get_hex_directions(cell.x)
    
    # Find closest direction using RENDER vectors
    var best_direction = 0
    var best_dot = -2.0
    
    for i in 6:
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

func check_victory() -> int:
    var active_sides = {}
    
    for cell in cell_list:
        if cell.side >= 0 and cell.side < Cell.MAX_SIDES and cell.get_troop_count() > 0:
            active_sides[cell.side] = true
    
    var active_count = active_sides.size()
    if active_count == 1:
        return active_sides.keys()[0]
    elif active_count == 0:
        return -2
    else:
        return -1

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
func on_board_updated():
    queue_redraw()

func on_cell_changed(cell: Cell):
    queue_redraw()

func _to_string() -> String:
    return "Board %dx%d (hex) with %d cells" % [width, height, cell_list.size()]
