class_name BoardRenderer
extends Control

# References
var game_manager: GameManager
var board: Board

# Display settings
@export var cell_size: int = 32
@export var border_width: int = 0
@export var show_grid: bool = false
@export var show_direction_vectors: bool = true
@export var show_troop_numbers: bool = false
var col_width: float = 0.0

# Colors (based on classic xbattle palette)
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

const terrain_colors = {
    -2: Color.CORNFLOWER_BLUE,    # Deep sea
    -1: Color.LIGHT_BLUE, # Shallow sea
    0: Color(0.9, 0.9, 0.6),  # Flat land
    1: Color(0.7, 0.8, 0.4),  # Low hills
    2: Color(0.6, 0.7, 0.3),  # Medium hills
    3: Color(0.5, 0.6, 0.2)   # High hills
}

# UI state
var selected_cell: Cell = null
var mouse_down: bool = false

func _ready():
    print("BoardRenderer ready")
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    gui_input.connect(_on_gui_input)
    if  game_manager and game_manager.board:
        calculate_scaling()

func _on_board_updated():
    if not game_manager:
        return
    board = game_manager.board
    queue_redraw()

func calculate_scaling():
    var viewport_size = get_viewport().get_visible_rect().size
    var wide = viewport_size.x / board.width
    var tall = viewport_size.y / board.height
    cell_size = min(wide, tall) * 0.98
    col_width = cell_size * 0.866   # sqrt(3)/2
    print("Calculated cell_size: %d" % cell_size)

func _on_cell_changed(cell: Cell):
    queue_redraw()

func _draw():
    if not board:
        return
    
    # Draw background
    draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
    
    # Draw each cell
    for cell in board.cell_list:
        draw_cell(cell)

func draw_cell(cell: Cell):
    var hex_points = get_hex_points(cell)
    
    # Draw terrain base
    var terrain_color = get_terrain_color(cell.level)
    draw_colored_polygon(hex_points, terrain_color)
    
    # Draw hex border
    var border_points = hex_points.duplicate()
    if (border_width > 0):
        border_points.append(hex_points[0])  # Close the polygon
        draw_polyline(border_points, Color.BLACK, border_width)
    
    # Draw troops if cell is occupied
    if cell.side >= 0 and cell.side < Cell.MAX_SIDES:
        var center = get_hex_center(cell)
        if cell.is_fighting():
            draw_fighting_cell_at_center(cell, center)
        else:
            draw_owned_cell_at_center(cell, center)
    
    # Draw town indicator
    if cell.is_town():
        draw_town_indicator_at_center(cell, get_hex_center(cell))
    
    # Draw direction vectors
    if show_direction_vectors and cell.side >= 0:
        draw_direction_vectors_at_center(cell, get_hex_center(cell))
    
    # Draw selection highlight
    if cell == selected_cell:
        draw_polyline(border_points, Color.WHITE, 3)

func get_hex_center(cell: Cell) -> Vector2:
    var x_pos = cell.x * col_width
    var y_pos = cell.y * cell_size + (cell.x % 2) * cell_size * 0.5
    return Vector2(x_pos + col_width * 0.5, y_pos + cell_size * 0.5)

func get_hex_points(cell: Cell) -> PackedVector2Array:
    var center = get_hex_center(cell)
    var radius = cell_size * 0.55
    var points = PackedVector2Array()
    
    for i in 6:
        var angle = PI / 3 * i
        var x = center.x + cos(angle) * radius
        var y = center.y + sin(angle) * radius
        points.append(Vector2(x, y))
    
    return points

func draw_owned_cell_at_center(cell: Cell, center: Vector2):
    var player_color = get_player_color(cell.side)
    var troop_count = cell.get_troop_count()
    
    if troop_count > 0:
        # Draw troop strength as filled circle
        var max_radius = cell_size * 0.3
        var radius = max_radius * (float(troop_count) / float(cell.get_max_capacity()))
        radius = max(radius, 3.0)  # Minimum visible size
        
        draw_circle(center, radius, player_color)
        
        # Draw troop count text
        if show_troop_numbers and troop_count > 1:
            var font = ThemeDB.fallback_font
            var text = str(troop_count)
            var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
            var text_pos = center - text_size / 2
            draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

func draw_fighting_cell_at_center(cell: Cell, center: Vector2):
    # Draw all sides with troops in combat
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
        
        # Draw pie slice for each side
        var start_angle = i * segment_angle
        var end_angle = (i + 1) * segment_angle
        
        var radius = 12.0 * (float(troops) / 10.0)  # Scale by troop count
        radius = clamp(radius, 4.0, 15.0)
        
        draw_arc(center, radius, start_angle, end_angle, 8, color, 3.0)

func draw_town_indicator_at_center(cell: Cell, center: Vector2):
    # Draw small square in hex to indicate town
    var indicator_size = Vector2(6, 6)
    var indicator_pos = center - indicator_size / 2
    var indicator_rect = Rect2(indicator_pos, indicator_size)
    
    draw_rect(indicator_rect, Color.WHITE)
    draw_rect(indicator_rect, Color.BLACK, false, 1)

func draw_direction_vectors_at_center(cell: Cell, center: Vector2):
    var directions = get_direction_vectors()
    
    for i in cell.direction_vectors.size():
        if i < directions.size() and cell.direction_vectors[i]:
            var dir_vec = directions[i]
            var end_pos = center + dir_vec * (cell_size * 0.3)
            
            # Draw arrow
            draw_line(center, end_pos, Color.WHITE, 2.0)
            draw_arrow_head(end_pos, dir_vec, Color.WHITE)

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
        return Color(0.4, 0.5, 0.1)  # Very high hills
    else:
        return Color(0.9, 0.9, 0.6)  # Default flat

func get_player_color(side: int) -> Color:
    if side >= 0 and side < player_colors.size():
        return player_colors[side]
    return Color.GRAY

func get_direction_vectors() -> Array[Vector2]:
    # 6-directional vectors for hex tiling
    return [
        Vector2(0, -1),   # UP
        Vector2(-0.866, -0.5),   # LEFT_UP
        Vector2(-0.866, 0.5),    # LEFT_DOWN
        Vector2(0, 1),    # DOWN
        Vector2(0.866, 0.5),     # RIGHT_DOWN
        Vector2(0.866, -0.5)     # RIGHT_UP
    ]

# Input handling
func _on_gui_input(event):
    if not board:
        return
    
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

func get_cell_at_position(pos: Vector2) -> Cell:
    var cell_x = int(pos.x / col_width)
    var cell_y = int((pos.y - (cell_x % 2) * cell_size * 0.5) / cell_size)
    return board.get_cell(cell_x, cell_y)

func handle_cell_click(cell: Cell, event: InputEventMouseButton):
    print("Clicked cell (%d,%d) side=%d troops=%d" % [cell.x, cell.y, cell.side, cell.get_troop_count()])
    if not game_manager:
        print("ERROR: no game_manager")
        return
    
    # For now, simple click sets direction toward cursor
    var cell_center = get_hex_center(cell)
    var direction_vec = (event.position - cell_center).normalized()
    
    # Find closest direction
    var directions = get_direction_vectors()
    var best_direction = 0
    var best_dot = -2.0
    
    for i in directions.size():
        var dot = direction_vec.dot(directions[i])
        if dot > best_dot:
            best_dot = dot
            best_direction = i
    
    # Toggle that direction
    var direction_mask = 1 << best_direction
    game_manager.handle_cell_click(cell, direction_mask)
    
    queue_redraw()

# Configuration functions
func set_cell_size(new_size: int):
    cell_size = new_size
    _on_board_updated()

func toggle_grid(enabled: bool):
    show_grid = enabled
    queue_redraw()

func toggle_direction_vectors(enabled: bool):
    show_direction_vectors = enabled
    queue_redraw()

func toggle_troop_numbers(enabled: bool):
    show_troop_numbers = enabled
    queue_redraw()
