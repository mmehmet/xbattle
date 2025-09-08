class_name GameManager
extends Node

var network_manager: NetworkManager

# Command constants
const CMD_ATTACK = 3
const CMD_DIG = 6
const CMD_FILL = 8
const CMD_BUILD = 10
const CMD_SCUTTLE = 12
const CMD_PARATROOPS = 14
const CMD_ARTILLERY = 16

# Cost constants
const COST_DIG = 30
const COST_FILL = 20
const COST_BUILD = 25

# Game state
@export var board: Board
@export var current_player: int = 0
@export var player_count: int = 2
@export var game_speed: float = 1.0
@export var is_paused: bool = false

# Game configuration (from original xbattle constants)
@export var fight_intensity: int = Cell.DEFAULT_FIGHT
@export var move_speed: int = Cell.DEFAULT_MOVE
@export var max_troop_capacity: int = Cell.MAX_MAXVAL
@export var enable_decay: bool = false
@export var enable_growth: bool = true

var update_timer: float = 0.0
var update_interval: float = 0.5  # Updates per second

# Signals for UI updates
signal board_updated
signal game_over(winner: int)
signal cell_changed(cell: Cell)

func _ready():
    print("GameManager ready")

# Initialize a new game
func start_new_game(config: Dictionary):
    var width = config.map_size.x
    var height = config.map_size.y
    player_count = config.player_count
    print("Starting new game: %dx%d board, %d players" % [width, height, player_count])
    
    # Get MY player side from network manager
    if network_manager:
        var my_info = network_manager.get_my_player_info()
        current_player = my_info.get("side", 0)
    else:
        current_player = 0
    
    is_paused = false
    
    if config.has("board_data"):
        # Client: receive board from host
        board = _deserialize_board(config.board_data)
        print("Client received board from host, playing as side %d" % current_player)
    else:
        # Host: generate new board
        board = Board.new(width, height)
        board.generate_terrain(config.hill_density, config.sea_density, config.forest_density)
        board.place_random_towns(config.town_density)
        board.place_player_bases(player_count, 1)
        print("Host generated board, playing as side %d" % current_player)
        if network_manager and network_manager.is_host:
            network_manager.set_board_of_truth(board)
    
    board_updated.emit()
    board.update_fog(current_player)

func _process(delta):
    if not board or is_paused:
        return
    
    update_timer += delta * game_speed
    if update_timer >= update_interval:
        update_timer = 0.0
        update_board()

# Main game update cycle (based on original update_board)
func update_board():
    if not board:
        return
    
    # Update fog of war visibility
    board.update_fog(current_player)
    
    # Randomize update order (important for fairness)
    var cell_order = board.cell_list.duplicate()
    cell_order.shuffle()
    
    # Update each cell
    for cell in cell_order:
        update_cell_growth(cell)
        update_cell_decay(cell)
        update_cell_combat(cell)
        update_cell_movement(cell)
    
    # Check for game over
    var winner = board.check_victory()
    if winner >= 0:
        game_over.emit(winner)
        print("Game Over! Winner: Player %d" % winner)
    elif winner == -2:
        game_over.emit(-1)  # Draw
        print("Game Over! Draw - all players eliminated")
    
    board_updated.emit()

# Update troop growth (towns and bases)
func update_cell_growth(cell: Cell):
    if not enable_growth or cell.growth <= 0 or cell.side < 0:
        return
    
    var max_capacity = cell.get_max_capacity()
    var current_troops = cell.get_troop_count()
    
    if current_troops < max_capacity:
        # Probabilistic growth based on original formula
        var growth_chance = cell.growth
        
        # Super towns can produce multiple troops per turn
        if cell.growth > Cell.TOWN_MAX:
            var guaranteed_troops = cell.growth / 100
            cell.add_troops(guaranteed_troops)
            growth_chance = cell.growth % 100
        
        # Random chance for additional troop
        if randi() % 100 < growth_chance:
            cell.add_troops(1)
            cell_changed.emit(cell)

# Update troop decay (optional feature)
func update_cell_decay(cell: Cell):
    if not enable_decay or cell.side < 0:
        return
    
    # Simple decay implementation
    var decay_chance = 2  # 2% chance per turn
    if randi() % 100 < decay_chance:
        var current_troops = cell.get_troop_count()
        if current_troops > 0:
            cell.set_troops(cell.side, current_troops - 1)
            if cell.get_troop_count() == 0:
                cell.side = Cell.SIDE_NONE
            cell_changed.emit(cell)

# Update combat resolution
func update_cell_combat(cell: Cell):
    if not cell.is_fighting():
        return
    
    # Get all sides with troops in this cell
    var sides_with_troops = {}
    for side in Cell.MAX_PLAYERS:
        if cell.troop_values[side] > 0:
            sides_with_troops[side] = cell.troop_values[side]
    
    if sides_with_troops.size() <= 1:
        # Combat resolved, assign winner
        if sides_with_troops.size() == 1:
            cell.side = sides_with_troops.keys()[0]
        else:
            cell.side = Cell.SIDE_NONE
        cell_changed.emit(cell)
        return
    
    # Calculate combat losses (based on original formula)
    var total_enemies = {}
    for side in sides_with_troops:
        total_enemies[side] = 0
        for other_side in sides_with_troops:
            if other_side != side:
                total_enemies[side] += sides_with_troops[other_side]
    
    # Apply losses
    for side in sides_with_troops:
        var my_troops = sides_with_troops[side]
        var enemy_troops = total_enemies[side]
        
        if enemy_troops > 0:
            var ratio = float(enemy_troops) / float(my_troops)
            var loss_factor = (ratio * ratio - 1.0 + randf() * 0.02) * fight_intensity
            
            if loss_factor > 0:
                var losses = int(loss_factor + 0.5)
                losses = min(losses, my_troops)
                cell.troop_values[side] = max(0, cell.troop_values[side] - losses)
    
    cell_changed.emit(cell)

# Update troop movement
func update_cell_movement(cell: Cell):
    if cell.move == 0 or cell.side < 0 or cell.is_fighting():
        return
    
    var current_troops = cell.get_troop_count()
    if current_troops <= cell.lowbound:
        return
    
    # Process each direction vector (in random order)
    var directions = range(Cell.MAX_DIRECTIONS)
    directions.shuffle()
    
    for dir in directions:
        if cell.direction_vectors[dir] and cell.connections[dir] != null:
            move_troops(cell, cell.connections[dir])

# Move troops between cells (core movement logic)
func move_troops(source: Cell, dest: Cell):
    if dest.level < Board.FLAT_LAND:
        return # Can't move into sea
    
    var source_troops = source.get_troop_count()
    var movable_troops = source_troops - source.lowbound
    
    if movable_troops <= 0:
        return
    
    # Calculate movement amount (simplified from original complex formula)
    var movement_modifier = dest.get_movement_modifier()
    var rate = move_speed * 0.1 # 30% movement rate by default
    var move_amount = int(float(movable_troops) * movement_modifier * rate)
    
    # Add randomness for small movements
    if move_amount == 0 and randf() < 0.3:
        move_amount = 1
    
    if move_amount <= 0:
        return
    
    # Ensure we don't exceed destination capacity
    var dest_capacity = dest.get_max_capacity()
    var dest_friendly_troops = 0
    if dest.side == source.side:
        dest_friendly_troops = dest.get_troop_count()
    
    move_amount = min(move_amount, dest_capacity - dest_friendly_troops)
    
    if move_amount <= 0:
        return
    
    # Execute the movement
    source.set_troops(source.side, source_troops - move_amount)
    
    if dest.side == Cell.SIDE_NONE:
        # Moving into empty cell
        dest.side = source.side
        dest.set_troops(source.side, move_amount)
        dest.age = 0
        if network_manager:
            network_manager.player_moved(dest)  # horizon has changed
    elif dest.side == source.side:
        # Moving into friendly cell
        dest.add_troops(move_amount)
    else:
        # Moving into enemy cell - start combat
        dest.troop_values[source.side] += move_amount
        dest.side = Cell.SIDE_FIGHT
    
    cell_changed.emit(source)
    cell_changed.emit(dest)

func on_cell_click(cell: Cell, direction_mask: int):
    if cell.side != current_player:
        return
    
    # Toggle the clicked direction
    for i in Cell.MAX_DIRECTIONS:
        if (direction_mask & (1 << i)) != 0:
            var current_state = cell.direction_vectors[i]
            cell.set_direction(i, not current_state)
    
    cell_changed.emit(cell)

func on_cell_command(cell: Cell, command: int):
    if command != CMD_DIG and command != CMD_FILL and cell.side != current_player:
        return

    match command:
        CMD_ATTACK: execute_attack(cell)
        CMD_DIG: execute_dig(cell)
        CMD_FILL: execute_fill(cell)
        CMD_BUILD: execute_build(cell)
        CMD_SCUTTLE: execute_scuttle(cell)
        CMD_PARATROOPS: execute_paratroops(cell)
        CMD_ARTILLERY: execute_artillery(cell)

func execute_attack(cell: Cell):
    # Basic attack - boost troop movement temporarily
    for i in Cell.MAX_DIRECTIONS:
        if cell.connections[i] != null:
            cell.set_direction(i, true)
    cell_changed.emit(cell)

func execute_dig(cell: Cell):
    if cell.level <= Board.DEEP_SEA:
        return # Already at min depth
       
    # Find adjacent friendly cell with enough troops
    for connection in cell.connections:
        if connection != null and connection.side == current_player and connection.get_troop_count() >= COST_DIG:
            connection.set_troops(connection.side, connection.get_troop_count() - COST_DIG)
            cell.level -= 1
            cell_changed.emit(cell)
            cell_changed.emit(connection)
            play_success_sound()
            return

func execute_fill(cell: Cell):
    # Raise terrain level, costs troops
    if cell.level > Board.HIGH_HILLS:
        return # nothing left to fill

    for connection in cell.connections:
        if connection != null and connection.side == current_player and connection.get_troop_count() >= COST_FILL:
            connection.set_troops(connection.side, connection.get_troop_count() - COST_FILL)
            cell.level += 1
            cell_changed.emit(cell)
            cell_changed.emit(connection)
            play_success_sound()
            return

func execute_build(cell: Cell):
    # Build/upgrade town
    if cell.growth >= Cell.TOWN_MAX:
        return

    if cell.get_troop_count() >= COST_BUILD:
        cell.set_troops(cell.side, cell.get_troop_count() - COST_BUILD)
        cell.growth = min(cell.growth + 25, Cell.TOWN_MAX)
        cell_changed.emit(cell)
        play_success_sound()

func execute_scuttle(cell: Cell):
    # Destroy all troops in cell
    cell.set_troops(cell.side, 0)
    cell.side = Cell.SIDE_NONE
    cell_changed.emit(cell)

func execute_paratroops(cell: Cell):
    # TODO: Implement airborne assault
    print("Paratroops not implemented yet - cell [%d,%d]" % [cell.x, cell.y])

func execute_artillery(cell: Cell):
    # TODO: Implement ranged attack
    print("Artillery not implemented yet - cell [%d,%d]" % [cell.x, cell.y])

# Game control functions
func pause_game():
    is_paused = true
    print("Game paused")

func resume_game():
    is_paused = false
    print("Game resumed")

func set_game_speed(speed: float):
    game_speed = clamp(speed, 0.1, 5.0)
    print("Game speed set to %fx" % game_speed)

func setup_network(nm: NetworkManager):
    network_manager = nm
    nm.set_game_manager(self)
    nm.player_left.connect(_check_victory.bind())

func _check_victory(player_info: Dictionary = {}):
    if network_manager.get_player_count() == 1:
        var remaining_players = network_manager.players.values()
        var winner = remaining_players[0].side
        game_over.emit(winner)

# Get game statistics
func get_game_stats() -> Dictionary:
    if not board:
        return {}
    
    var stats = board.get_stats()
    stats["current_player"] = current_player
    stats["player_count"] = player_count
    stats["is_paused"] = is_paused
    stats["game_speed"] = game_speed
    
    return stats

# Configuration functions
func set_fight_intensity(intensity: int):
    fight_intensity = clamp(intensity, 1, 10)
    print("Fight intensity set to %d" % fight_intensity)

func set_move_speed(speed: int):
    move_speed = clamp(speed, 1, 10)
    print("Move speed set to %d" % move_speed)

func toggle_decay(enabled: bool):
    enable_decay = enabled
    print("Decay %s" % ("enabled" if enabled else "disabled"))

func toggle_growth(enabled: bool):
    enable_growth = enabled
    print("Growth %s" % ("enabled" if enabled else "disabled"))

# Misc
func array_intersect(a1: Array, a2: Array) -> Array:
    var result = []
    for item in a1:
        if a2.has(item):
            result.append(item)
    return result

func play_success_sound():
   var audio = AudioStreamPlayer.new()
   add_child(audio)
   audio.stream = load("res://assets/dirt.mp3")
   audio.play()
   audio.finished.connect(func(): audio.queue_free())

func _deserialize_board(data: Dictionary) -> Board:
    print("Deserializing board with %d cells" % data.cells.size())
    var board = Board.new(data.width, data.height)
    
    for cell_data in data.cells:
        var cell = board.get_cell_by_index(cell_data.index)
        cell.side = cell_data.side
        cell.troop_values = cell_data.troops
        cell.level = cell_data.level
        cell.growth = cell_data.growth
    
    print("Deserialized board: first cell side=%d, level=%d" % [board.cell_list[0].side, board.cell_list[0].level])
    return board
