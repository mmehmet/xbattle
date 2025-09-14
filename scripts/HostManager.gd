class_name HostManager
extends Node

var board: Board
var network_manager: NetworkManager

# Cost constants
const COST_DIG = 30
const COST_FILL = 20
const COST_BUILD = 25

# Game configuration (from original xbattle constants)
@export var fight_intensity: int = Cell.DEFAULT_FIGHT
@export var move_speed: int = Cell.DEFAULT_MOVE
@export var max_troop_capacity: int = Cell.MAX_MAXVAL

var update_timer: float = 0.0
var update_interval: float = 0.5  # Updates per second

func _ready():
    set_process(true)

func setup(nm: NetworkManager, board_of_truth: Board, bases: Array[Cell]):
    network_manager = nm
    board = board_of_truth
    for base in bases:
        nm.send_cell_delta(base)

func _process(delta):
    update_timer += delta
    if update_timer >= update_interval:
        update_timer = 0.0
        update_board()

# Main game update cycle (based on original update_board)
func update_board():
    if not board:
        return
    
    # Randomize update order (important for fairness)
    var cells = board.cell_list.duplicate()
    cells.shuffle()
    for cell in cells:
        update_cell_growth(cell)
        update_cell_decay(cell)
        update_cell_combat(cell)
        update_cell_movement(cell)
    
    # Send updates
    for cell in cells:
        if cell.outdated:
            network_manager.send_cell_delta(cell)
            cell.outdated = false
    
    # Check for game over
    var sides = network_manager.players.values().map(func(p): return p.side)
    var active = board.get_active(sides)
    network_manager.update_active(active)
    network_manager.check_victory()

# receive update from the UI
func update_cell(data: Dictionary):
    var cell = board.get_cell_by_index(data.cell_index)
    if cell:
        cell.side = data.side
        cell.troop_values = data.troops
        cell.level = data.level
        cell.growth = data.growth
        cell.direction_vectors = data.directions
        cell.move = cell.get_active_directions()

        var cells = board.cell_list.filter(func(c): return cell.get_distance(c) <= Cell.HORIZON)
        for player in network_manager.players.values():
            # always see your own cells
            cell.seen_by[player.side] = (cell.side == player.side)

            if not cell.seen_by[player.side]:
                for check in cells:
                    if check.side == player.side:
                        cell.seen_by[player.side] = true
                        break
        network_manager.send_cell_delta(cell)
                
# Update troop growth (towns and bases)
func update_cell_growth(cell: Cell):
    if cell.growth <= 0 or cell.side < 0:
        return
    
    var max_capacity = cell.get_max_capacity()
    var current_troops = cell.get_troop_count()
    if current_troops < max_capacity:
        var growth_chance = cell.growth
        
        # Super towns can produce multiple troops per turn
        if cell.growth > Cell.TOWN_MAX:
            var guaranteed_troops = cell.growth / 100
            cell.add_troops(guaranteed_troops)
            growth_chance = cell.growth % 100
            cell.outdated = true
        
        # Random chance for additional troop
        if randi() % 100 < growth_chance:
            cell.add_troops(1)
            cell.outdated = true

# Update troop decay (optional feature)
func update_cell_decay(cell: Cell):
    if cell.side < 0:
        return
    
    # Simple decay implementation
    var decay_chance = 2  # 2% chance per turn
    if randi() % 100 < decay_chance:
        var current_troops = cell.get_troop_count()
        if current_troops > 0:
            cell.set_troops(cell.side, current_troops - 1)
            cell.outdated = true
            if cell.get_troop_count() < 1:
                cell.side = Cell.SIDE_NONE

# Update combat resolution
func update_cell_combat(cell: Cell):
    if not cell.is_fighting():
        return
    
    var result = get_combat_state(cell)
    if result.count <= 1:
        cell.outdated = true
        cell.side = result.winner
        return
    
    # Calculate/apply combat losses
    cell.outdated = true

    var combatants = {}
    for side in Cell.MAX_PLAYERS:
        if cell.troop_values[side] > 0:
            combatants[side] = {
                "own": cell.troop_values[side],
                "enemy": result.total - cell.troop_values[side],
                "attack_vectors": 0
            }
            for neighbor in cell.connections:
                if neighbor and neighbor.side == side:
                    combatants[side]["attack_vectors"] += 1
            
    var sides = combatants.keys()
    sides.shuffle()

    for side in sides:
        var data = combatants[side]
        if data["enemy"] > 0:
            var attack_bonus = 1.0 + (data["attack_vectors"] * 0.1)  # +10% per supporting cell
            var base_loss = min(data["own"], data["enemy"]) * 0.1 * attack_bonus
            var losses = max(1, int(base_loss * (0.8 + randf() * 0.4)))
            
            cell.troop_values[side] = max(0, cell.troop_values[side] - losses)

    # check for winner after losses
    var outcome = get_combat_state(cell)
    if outcome.count <= 1:
        cell.side = outcome.winner

func get_combat_state(cell: Cell) -> Dictionary:
    var winner = Cell.SIDE_NONE
    var count = 0
    var total_troops = 0
    
    for side in Cell.MAX_PLAYERS:
        if cell.troop_values[side] > 0:
            winner = side
            count += 1
            total_troops += cell.troop_values[side]
    
    return {"winner": winner, "count": count, "total": total_troops}

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
    elif dest.side == source.side:
        # Moving into friendly cell
        dest.add_troops(move_amount)
    else:
        # Moving into enemy cell - start combat
        var current = dest.troop_values[source.side]
        var max_capacity = dest.get_max_capacity()
        dest.troop_values[source.side] = min(current + move_amount, max_capacity)
        dest.side = Cell.SIDE_FIGHT
        dest.clear_directions()
    
    source.outdated = true
    dest.outdated = true

func execute_attack(idx: int, side: int):
    var cell = board.get_cell_by_index(idx)
    if not cell or cell.side != side:
        return
    
    for i in Cell.MAX_DIRECTIONS:
        if cell.connections[i] != null:
            cell.set_direction(i, true)
    
    network_manager.send_cell_delta(cell)

func execute_dig(idx: int, side: int):
    var cell = board.get_cell_by_index(idx)
    if not cell or cell.level < Board.SHALLOW_SEA or cell.growth > 0:
        return # cell contains a town or is already deep water

    for troops in cell.troop_values:
        if troops > 0:
            return # cell contains troops

    # Find adjacent friendly cell with enough troops
    for connection in cell.connections:
        if connection and connection.side == side and connection.get_troop_count() >= COST_DIG:
            connection.set_troops(connection.side, connection.get_troop_count() - COST_DIG)
            cell.level -= 1
            network_manager.send_cell_delta(cell, true)
            network_manager.send_cell_delta(connection)
            return

func execute_fill(idx: int, side: int):
    var cell = board.get_cell_by_index(idx)
    if not cell or cell.level > Board.LOW_HILLS or cell.growth > 0:
        return # cell contains a town or is already high hills

    for troops in cell.troop_values:
        if troops > 0:
            return # cell contains troops

    # Find adjacent friendly cell with enough troops
    for connection in cell.connections:
        if connection and connection.side == side and connection.get_troop_count() >= COST_FILL:
            connection.set_troops(connection.side, connection.get_troop_count() - COST_FILL)
            cell.level += 1
            network_manager.send_cell_delta(cell, true)
            network_manager.send_cell_delta(connection)
            return

func execute_build(idx: int, side: int):
    # Build/upgrade town
    var cell = board.get_cell_by_index(idx)
    if not cell or cell.side != side:
        return
        
    if cell.growth >= Cell.TOWN_MAX:
        return # town already fully upgraded 

    if cell.get_troop_count() >= COST_BUILD:
        cell.set_troops(cell.side, cell.get_troop_count() - COST_BUILD)
        cell.growth = min(cell.growth + 25, Cell.TOWN_MAX)
        network_manager.send_cell_delta(cell, true)

func execute_scuttle(idx: int, side: int):
    # Destroy town in cell
    var cell = board.get_cell_by_index(idx)
    if not cell or cell.side != side:
        return
        
    # Destroy town in cell
    cell.growth = 0
    network_manager.send_cell_delta(cell, true)

func execute_paratroops(idx: int, side: int):
    # TODO: Implement airborne assault
    print("Paratroops not implemented yet - cell [%d]" % idx)

func execute_artillery(idx: int, side: int):
    # TODO: Implement ranged attack
    print("Artillery not implemented yet - cell [%d]" % idx)
