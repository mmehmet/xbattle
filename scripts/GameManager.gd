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
    print("DEBUG: start_new_game called, has board_data=%s, is_host=%s" % [config.has("board_data"), network_manager.is_host if network_manager else false])
    
    if network_manager and network_manager.is_host and not config.has("board_data"):
        # Host generates and sends board data to clients
        board = Board.new(width, height)
        board.generate_terrain(config.hill_density, config.sea_density, config.forest_density)
        board.place_random_towns(config.town_density)
        var bases = board.place_player_bases(player_count)
        print("Host generated board, playing as side %d" % current_player)
        
        var board_data = network_manager.serialize_board(board, bases)
        network_manager.rpc_all_clients("_receive_board_data", board_data)
        config["board_data"] = board_data  # So we take client path below
    
    # Get MY player side from network manager
    if network_manager:
        var my_info = network_manager.get_my_player_info()
        current_player = my_info.get("side", 0)
    else:
        current_player = 0
    
    if not config.has("board_data"):
        return
    
    is_paused = false

    # Client: receive board from host
    board = _deserialize_board(config.board_data)
    print("Client received board from host, playing as side %d" % current_player)
    
    board_updated.emit()
    if board:
        board.update_fog(current_player, board.get_cells_for_side(current_player))

func concede_defeat():
    if player_count == 2:
        var opponent = 1 - current_player
        game_over.emit(opponent)
    else:
        game_over.emit(-1)  # Multi-player concede
    print("Player %d conceded" % current_player)

func on_cell_click(cell: Cell, direction_mask: int):
    if cell.side != current_player:
        return
    
    # Toggle the clicked direction
    for i in Cell.MAX_DIRECTIONS:
        if (direction_mask & (1 << i)) != 0:
            var current_state = cell.direction_vectors[i]
            cell.set_direction(i, not current_state)
    
    cell_changed.emit(cell)
    network_manager.send_click(cell)

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

    if cell.growth > 0:
        return # cell contains a town

    for troops in cell.troop_values:
        if troops > 0:
            return # cell contains troops

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

    if cell.growth > 0:
        return # cell contains a town

    for troops in cell.troop_values:
        if troops > 0:
            return # cell contains troops

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
    # Destroy town in cell
    cell.growth = 0
    cell_changed.emit(cell)
    play_success_sound()

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
    print("DEBUG: GameManager.setup_network, nm.is_host=%s" % nm.is_host)
    nm.set_game_manager(self)

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

# Misc
func play_success_sound():
   var audio = AudioStreamPlayer.new()
   add_child(audio)
   audio.stream = load("res://assets/dirt.mp3")
   audio.play()
   audio.finished.connect(func(): audio.queue_free())

func _deserialize_board(data: Dictionary) -> Board:
    print("Deserializing board with %d cells" % data.cells.size())
    var temp = Board.new(data.width, data.height)
    
    for cell_data in data.cells:
        var cell = temp.get_cell_by_index(cell_data.index)
        cell.side = cell_data.side
        cell.troop_values = cell_data.troops
        cell.level = cell_data.level
        cell.growth = cell_data.growth
    
    return temp
