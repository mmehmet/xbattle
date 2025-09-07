# CORE XBATTLE GAME MECHANICS
### Board System

- **Tiling types**: Hexagonal ONLY
- **Board size**: Configurable, default 15x15 (up to 50x50 max)
- **Cell capacity**: Each cell has `maxval` (default 20, max 50) troop limit
- **Terrain levels**: Hills (+), Sea (-), Forest, with movement penalties
- **Wrapping**: Optional board edge wrapping

### Core Data Structures
#### Cell Properties:

```c
typedef struct {
    s_char side;              // Owner (0-10, or SIDE_NONE, SIDE_FIGHT)
    s_char *value;            // Troop count per side [0-maxval]
    s_char level;             // Terrain elevation
    s_char growth;            // Town production rate (0-255)
    s_char move;              // Number of active direction vectors
    s_char *dir;              // Direction vector array [0-6 directions]
    s_char age;               // How long owned by same side
    // ... plus march, visibility, etc.
} cell_type;
```

### Movement & Combat System
#### Troop Movement:

```c
// Movement calculation (from update_cell):
nmove = surplus * 
        move_hinder[dest_level] *      // Terrain difficulty
        move_shunt[current_troops] *   // Supply line attenuation  
        move_speed *                   // Speed setting
        (1.0 - move_slope[level_diff]) // Hill penalty
```

#### Combat Resolution:

- When enemy troops meet: `cell->side = SIDE_FIGHT`
- Combat is **probabilistic** based on troop ratios
- Loss calculation: `loss = ((enemy_ratio^2) - 1.0 + random) * fight_intensity`
- Winner takes cell when only one side remains

### Key Game Constants
```c
#define MAX_PLAYERS        11
#define MAX_DIRECTIONS      6
#define MAXVAL             50  // Max troops per cell
#define TOWN_MIN           50  // Minimum town production
#define TOWN_MAX          100  // Maximum town production

// Default values:
#define DEFAULT_BOARD      15  // Board size
#define DEFAULT_MAXVAL     20  // Cell capacity
#define DEFAULT_FIGHT       5  // Combat intensity
#define DEFAULT_MOVE        3  // Movement speed
```

### Town/Base System

- **Growth rate**: Towns produce troops probabilistically each turn
- **Super towns**: `growth > 100` produce multiple troops per turn
- **Production formula**: `if (growth > random(100)) add_troop()`

### Special Commands
```c
#define CMD_ATTACK         3   // Attack command
#define CMD_DIG            6   // Lower terrain
#define CMD_FILL           8   // Raise terrain  
#define CMD_BUILD         10   // Build cities
#define CMD_SCUTTLE       12   // Destroy troops
#define CMD_PARATROOPS    14   // Airborne attack
#define CMD_ARTILLERY     16   // Ranged attack
#define CMD_MARCH_*       20   // Automated movement
```

### Advanced Features
#### Supply Lines:

- Troops weaken with distance from bases
- `move_shunt[]` array controls attenuation
- **Disrupt**: Enemies can break supply lines

### Fog of War:

- **Horizon**: Limited visibility range
- **Local mapping**: Terrain disappears when unoccupied

### Terrain Operations:

- **Dig**: Lower terrain (costs troops)
- **Fill**: Raise terrain (costs troops)
- **Build**: Construct cities segment by segment

### Game Loop Structure
```c
// Main update cycle (from update_board):
1. Randomize cell update order
2. For each cell:
   - Update growth (troop production)
   - Handle managed operations
   - Process decay
   - Resolve combat if fighting
   - Process movement in random direction order
3. Redraw changed cells
```

### Critical Implementation Notes

#### Movement Processing:

- Cells update in **random order** each turn
- Direction vectors processed in **random order**
- **Probabilistic movement**: Fractional troops have chance to move

#### Combat Mechanics:

- Non-linear based on troop ratios
- Includes randomness factor
- **NOSPIGOT**: Auto-retreat when outnumbered

#### Supply Line Math:

- Complex attenuation based on distance and terrain
- Different curves for hills vs flat terrain
