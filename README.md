# BAREMETAL

![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=x86-64&rightText=assembly&badgeColor=808000&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=Linux+only&rightText=Static+binary&badgeColor=804000&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=Intel+syntax&badgeColor=004080&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=14KB+code&rightText=280KB+data%2Bbss&badgeColor=400040&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=69KB&rightText=Executable&badgeColor=203040&textColor=ffffff)

<img width="1000" alt="baremetal_v1_1_0" src="https://github.com/user-attachments/assets/05a915ea-f934-421b-a707-9c60d18760c5" />


A Wolfenstein-3D-style DDA raycaster written entirely in x86-64 assembly. Runs at 60fps in any Linux terminal. No libc, no FPU, no framebuffer, and a 69KB static binary.

## Constraints

Entry point is `_start`. No malloc, printf, memcpy. Every syscall is a raw `syscall` instruction. All memory is statically allocated in `.data` or `.bss`: sizes fixed at link time. The FPU is never touched; trigonometry runs on integer registers via LUTs and Q8 fixed-point. One `write(1, buf, len)` per frame: no per-character writes, no ioctl inside the render path.

## Build

```bash
make          # build ./baremetal
make run      # build and run
make clean    # remove *.o and binary
```

Assembler: `nasm -f elf64 -g -F dwarf`. Linker: `ld -static`. DWARF debug info on by default; strip for production.

## Module Map

```text
baremetal/
├── src/
│   ├── core/
│   │   ├── entry.asm         ; _start, fixed-timestep game loop, shutdown
│   │   └── game.asm          ; world map (32×32), player state, DDA raycaster, door/enemy/AI
│   ├── platform/
│   │   ├── terminal.asm      ; termios raw mode, alt screen, TIOCGWINSZ, signal handlers
│   │   ├── input.asm         ; poll+read drain loop, key state flags
│   │   └── timing.asm        ; clock_gettime(CLOCK_MONOTONIC), elapsed_ns, nanosleep
│   ├── math/
│   │   └── math.asm          ; sin/cos LUTs (×1024, 360 entries), Q8 helpers, int_to_ascii
│   └── render/
│       ├── render.asm        ; frame buffer, raycaster projection, sprites, gun HUD, game over
│       ├── render_data.asm   ; all data: colors, sprites, fonts, HUD strings
│       ├── render_utils.asm  ; buffer helpers, cursor moves, pixel sprite drawing
│       └── render_start.asm  ; start screen pixel-art rendering
├── Makefile
├── LICENSE                   ; GPLv3
├── TECHNICAL.md              ; full technical design document
└── README.md
```

Cross-module linkage is `global`/`extern` only. No shared headers: symbol names are the ABI.

## Game Loop

Fixed 60fps timestep. `FRAME_NS = 16666666`.

```nasm
init_terminal → get_terminal_size → init_game → render_init → render_start_screen:
  wait for any key
  game loop:
    get_time(time_start)
    process_input
    quit_flag? → shutdown
    toggle_door (if key_use)
    resize_flag? → get_terminal_size + render_init
    update_game (movement, enemies, shooting, lights)
    render_frame (raycaster → sprites → gun → HUD → flush)
    get_time(time_current)
    elapsed = elapsed_ns(time_start, time_current)
    if FRAME_NS - elapsed > 0: sleep_remaining(FRAME_NS - elapsed)
```

`nanosleep` woken by a signal returns early with `EINTR`. The loop doesn't retry: it just runs the next frame. At 60fps the drift is imperceptible.

## Feature Summary

| Feature             | Notes                                                   |
| ------------------- | ------------------------------------------------------- |
| DDA raycaster       | Perpendicular distance, 64 max steps                    |
| 5 wall types        | Stone, brick, metal, wood, door with procedural shaders |
| 4-distance shading  | █▓▒░ with color escapes per wall type                   |
| 3 point lights      | Static, pulsing, muzzle flash                           |
| 8 sprites (4 types) | Barrel, pillar, key, enemy/corpse                       |
| Enemy AI            | Chase, attack, hurt, death states                       |
| Hitscan combat      | Dot/cross product hit detection                         |
| Doors               | Toggle via E, open doors pass rays                      |
| Gun HUD             | Pistol + hand + muzzle flash sprites                    |
| Start screen        | Pixels font, controls box                               |
| Game over           | Red fill, centered text                                 |
| Minimap             | 16×16 scrolling, directional marker                     |
| FPS counter         | Rolling 60-frame average                                |
| Terminal handling   | Raw mode, alt screen, 4 signals, resize                 |
| Math LUTs           | 360-entry sin/cos ×1024, int_to_ascii                   |

## Terminal (`terminal.asm`)

Init: `ioctl(TCGETS)` to save termios, then modify in place: clear `ICANON | ECHO | ISIG | IEXTEN` from `c_lflag`, `OPOST` from `c_oflag`, `BRKINT | ICRNL | INPCK | ISTRIP | IXON` from `c_iflag`, set `VMIN=0 VTIME=0`. Apply via `ioctl(TCSETS)`. Then `ESC[?1049h` (alternate screen), `ESC[?25l` (hide cursor), `ESC[2J` (clear once). Signal handlers last.

Restore: `ioctl(TCSETS)` with the saved struct, `ESC[?1049l`, `ESC[?25h`, `ESC[0m`.

`sigaction` uses `SA_RESTORER` with a trampoline that calls `rt_sigreturn` (syscall 15). Required by the kernel on x86-64.

**Signals handled:**

- `SIGINT`, `SIGTERM`, `SIGSEGV` → `restore_terminal` + `exit(1)`
- `SIGWINCH` → sets `resize_flag`, consumed in game loop

`get_terminal_size`: `ioctl(TIOCGWINSZ)`. Falls back to 80×24. Column count is decremented by 1 as a safety margin against escape-sequence wrapping.

The kernel `termios` struct layout (not glibc's):

```nasm
 0: c_iflag  (4 bytes)
 4: c_oflag  (4 bytes)
 8: c_cflag  (4 bytes)
12: c_lflag  (4 bytes)
16: c_line   (1 byte)
17: c_cc[19]: VTIME at [5] (offset 22), VMIN at [6] (offset 23)
```

## Input (`input.asm`)

Each frame: zero all direction flags, drain stdin with `poll(timeout=0)` + `read(1 byte)` in a loop. Last key wins per axis; W cancels S, A cancels D, and vice versa. Non-opposing pairs (W+D) can coexist. Space shoots, E toggles doors, Q quits.

Keys: `W/A/S/D` (move/turn), `E` (use door), `Space` (shoot), `Q` (quit). Case-insensitive.

## Fixed-Point

Q8: real value encoded as `real × 256`. Integer part in bits 63..8, fraction in 7..0. Addition and subtraction work directly on encoded values. Map cell index from Q8: `sar rax, 8`.

The LUTs are scaled ×1024. After a LUT multiply, shift right by 10:

```nasm
imul rax, [cos_table + rdi*8]
sar  rax, 10                    ; Q8 result
```

×1024 eliminates stair-stepping at typical screen sizes that ×256 produces.

## Math (`math.asm`)

`sin_table` / `cos_table`: 360 × `dq` in `.data`, precomputed as `round(sin/cos(i°) × 1024)`. ~5.6KB total.

`int_to_ascii(rax=value, rdi=dest)`: divide-by-10 loop into `digit_buf`, write forward. Returns `rdi` past last byte, `rax` = byte count. Preserves `rbx`, `r12`–`r15`. Zero handled as special case before the loop.

`lut_mul(rdi=Q8, rsi=LUT_val)`: `(rdi × rsi) >> 10`. Returns Q8.

`fp_div(rdi, rsi)`: `(rdi << 8) / rsi`. Used to compute `delta_dist` in DDA setup.

`abs_val(rdi)`: branchless via `cqo` / `xor` / `sub`.

## World Map (`game.asm`)

1024-byte array, row-major, 32×32. Cell values: `0=open`, `1=stone`, `2=brick`, `3=metal`, `4=wood`, `5=door`.

Layout: four quadrants separated by a central cross-corridor at rows/cols 15–16.

- NW (brick): rows 1–14, cols 1–14
- NE (metal): rows 1–14, cols 17–30
- SW (wood): rows 17–30, cols 1–14
- SE (stone): rows 17–30, cols 17–30

Each quadrant has an inner room with doorways at the corridor edges. Corridor walls at rows 14/17 and cols 14/17 have door cells (`5`). The corridor itself (rows 15–16, cols 1–30) and the central cross (rows 0–31, cols 15–16) are open.

Player spawns at `(15<<8)|128` on both axes: map cell (15, 15), fractional offset 0.5, center of corridor, facing east (angle 0). The non-integer start prevents `side_dist = 0` at the first grid line.

Cell lookup: `world_map[map_y * 32 + map_x]`.

Door state tracked in parallel `door_state` array (byte per cell), toggled by `E` near a door cell.

## DDA Raycaster (`game.asm: cast_ray`)

```nasm
in:  rdi = ray angle (0..359)
out: rax = perpendicular wall distance (map units × 1024), min 1
     rdx = wall type (1-5) of the cell that was hit
     rcx = side (0=x-wall, 1=y-wall)
```

`delta_dist_x/y = |1024² / ray_dir_x/y|`: distance between consecutive grid crossings on each axis. Zero direction component → `DDA_INF (0x3FFFFFFFFFFFFFFF)` for that axis.

Initial `side_dist` computed from fractional part of Q8 player position. Negative ray direction: `(frac × delta) >> 8`. Positive: `((256 - frac) × delta) >> 8`.

DDA loop: compare `side_dist_x` vs `side_dist_y`, step the smaller, increment map coordinate, check `world_map`. Max 64 iterations (safety; perimeter walls are hit first).

**Perpendicular distance** at hit: `side_dist_at_hit - delta_dist`. This is the distance to the crossed grid line measured perpendicular to the view plane, mind it's not Euclidean. Directly cancels fisheye distortion. No separate cosine correction.

Wall collision in `update_game` tests X and Y independently: proposed `new_x` checked with current `map_y`, proposed `new_y` checked with the (possibly already updated) `map_x`. Both axes can move in the same frame - wall sliding.

## Lighting (`game.asm`)

3 point lights, each with position (Q8), radius² (Q8 units), intensity (0–10), and type:

| Light | Position                | Type         | Behavior                              |
| ----- | ----------------------- | ------------ | ------------------------------------- |
| 0     | Corridor center (16,16) | Static white | Always on, intensity 4                |
| 1     | NW brick room (5,5)     | Pulsing red  | Toggles intensity 1↔6 every 16 frames |
| 2     | Player position         | Muzzle flash | Intensity 10 for 4 frames on shoot    |

During wall rendering, each column's hit point is tested against all 3 light radius² bounds. The max intensity found reduces the shade tier: `tier -= intensity / 2`, clamped to 0 (brightest).

## Enemy AI (`game.asm: update_enemies`)

2 enemies (state machine: 0=Inactive, 1=Chase, 2=Hurt, 3=Dead):

- **Chase**: If player within 16-cell Manhattan distance, move toward player at speed 4 (Q8). Pathfinding via `is_passable` check with independent X/Y sliding.
- **Attack**: If within 0.75-cell Manhattan distance, deal 10 damage every 32 frames.
- **Hurt**: On hit (stun for 10 frames), returns to Chase.
- **Dead**: State 3. Sprite switches to corpse type.
- **Death**: 3 hitscan shots (34 damage each) to kill (100 HP).

## Hitscan Combat (`game.asm`)

On Space: compute perpendicular distance at center column from Z-buffer. For each living enemy, compute `dot = dx·cos + dy·sin` (distance in front). If enemy is in front and closer than the wall, compute `cross = cos·dy - sin·dx` (lateral offset). If `abs(cross) < 64` (0.25-cell hitbox), hit.

## Render (`render.asm`)

128KB static frame buffer (actually 256KB). `buf_pos` is the write head. Single `write(1, frame_buffer, len)` at end of frame. Sync markers (`ESC[?2026h` / `ESC[?2026l`) enable atomic terminal updates on xterm.js.

`clear_buffer`: resets `buf_pos`, writes `ESC[H` + sync start. Cursor home, not clear: the alt screen overwrites in place, no blank flash.

`render_init`: draws box border and blanks interior. Called once at startup and on SIGWINCH resize.

`render_frame` runs in passes:

**Pass 1 (Raycast)**: For each column `c` (0..render_scr_cols-1):

```
angle  = player_angle - 30 + (c × 60 / (render_scr_cols - 1)), normalised to [0,359]
dist   = cast_ray(angle) → perp_dist × 1024
wall_h = (render_scr_rows × 1024) / dist, capped at render_scr_rows
top    = (render_scr_rows - wall_h) / 2
bot    = top + wall_h - 1
shade  = dist < 2048 → █ | < 4096 → ▓ | < 8192 → ▒ | else → ░
```

Results stored in `col_char[c]`, `col_color[c]`, `col_top[c]` (word), `col_bot[c]` (word), `col_wall_type[c]`. U-coordinate (0–255) saved for procedural texturing. Distance saved to Z-buffer.

Pass 1 also computes wall hit coordinates for point-light testing and U/V texture coordinates.

**Pass 2 (Row-major emit)**: Per row: cursor move, then per column. Ceiling above wall top: star field (`▪`/`.`/` ` based on hash of row×col). Wall: color escape (5 types × 4 distance tiers + light reduction) followed by shade block char. Floor: carpet (`▒`) with 3-band depth shading.

**Procedural Shaders** (5 wall types):

- Stone: solid with 32-cell edge border (▓ border, █ fill)
- Brick: Wolfenstein-style staggered, 16-cell mortar gap
- Metal: XOR grate pattern (every 64 cells)
- Wood: vertical panel strips (32-cell period)
- Door: panel with horizontal lock band, 24-cell border

**Minimap**: 16×16 scrolling viewport, top-right of screen. `#` = wall, `.` = floor, `+` = closed door, directional marker (`>v<^`) for player. Viewport follows player, clamped at map edges.

**Sprite pass** (Painter's Algorithm):

1. For each of 8 sprites, compute camera-space transform: `trans_y = (dx·cos + dy·sin) >> 8`, `trans_x = (-dx·sin + dy·cos) >> 8`. If behind player, skip.
2. Sort sprites by `trans_y` descending (bubble sort, max 8. Negligible cost).
3. For each sprite: compute screen position, scale by per-type factors (Q8), clamp to screen bounds. For each pixel within bounding box, check Z-buffer, compute UV, run per-type shader (barrel/pillar/enemy/corpse/key), emit shaded block.

**Gun HUD**: Overlaid on bottom-center of screen. 24×9 pistol sprite + 24×8 hand sprite below it. Muzzle flash (24×6, yellow) drawn above pistol for first 4 frames of fire animation. All rendered via fixed screen-space coordinates (no projection). Recoil effect: gun shifts down 1 row during fire.

**Start Screen**: Pixel-font "BAREMETAL" title (9 chars × 5 rows, pixel font in `font_table`), subtitle, controls box (WASD/E/Q with descriptions), "PRESS ANY KEY TO START" prompt.

**Game Over Screen**: Red background fill, centered pixel-font "GAME OVER" in black, "[ PRESS Q TO QUIT ]" subtitle in yellow.

**HUD**: Bottom line (row = `term_rows`): `FPS:##  POS:##,##  ANG:###  HP:###  [GAME OVER]`.

## ABI

SysV x86-64. `rbx`, `rbp`, `r12`–`r15` are callee-saved: push/pop at function entry/exit if used. Everything else is caller-saved; assume destroyed after any call. Stack is 16-byte aligned before `call`. Signal handlers run on the same stack; red zone below `rsp` is not safe to use.

## Debugging

```bash
gdb ./baremetal
(gdb) layout asm
(gdb) layout regs
(gdb) b cast_ray
(gdb) b render_frame
(gdb) si
(gdb) x/32xb &world_map
(gdb) x/gd &player_x            # raw Q8 value
(gdb) p *(long*)&player_x >> 8  # map cell
```

Terminal stuck after crash: `reset`.

## Known Issues

- `term_cols - 1` safety margin in `get_terminal_size` is a workaround for escape-sequence wrapping at the last column. The renderer doesn't account for the byte-width of escape codes when computing column positions.
- Angle normalisation does one add or subtract. If `ROT_SPEED` were ever >= 360 this would wrap incorrectly (currently 5).
- DDA iteration cap is 64. Fine for a 32×32 map. Raise it if the map grows past `(MAP_WIDTH + MAP_HEIGHT) * 2 > 64`.
- The lighting system is still immature.

## License

The code is licensed under the GPL-3.0 license.
