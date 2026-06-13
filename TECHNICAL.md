# BAREMETAL

### A Terminal Game Engine in x86-64 Assembly

**A First-Person Raycaster in Pure x86-64 Assembly**
_Zero Dependencies_

---

## VISION

A game engine to render a 3D first-person perspective inside a terminal that runs entirely on bare Linux syscalls with no standard library or C runtime.

- 60fps fixed-timestep game loop
- Zero floating-point math (Q8 fixed-point + integer-only)
- No standard library, or CRT, or FPU instructions
- Single `write(1, buf, len)` per frame
- All memory statically allocated

---

## ARCHITECTURAL DECISIONS

### Language: NASM, Intel syntax

Destination first. Standalone `.asm` files assembled to `.o`, linked statically.

### No libc. No CRT.

Entry point is `_start`. No `printf`, `malloc`, or `sleep`. Every syscall is `syscall` with the Linux x86-64 ABI: arguments in `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`. Number in `rax`. Return value in `rax`.

### Target: x86-64 Linux

Syscall convention: arguments in `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`. Number in `rax`. Return value in `rax`.

### Memory: Static allocation only

No heap. All memory declared upfront in `.bss` (zeroed at load) or `.data` (initialised). Frame buffer is 256KB, sufficient for worst-case render output including color escapes.

### The terminal is a grid. Embrace it.

Coordinates are 1-indexed integer cells. No sub-cell positions or diagonal movement. One direction per frame, last key seen wins per axis. Terminal escape codes are the GPU.

---

## SYSCALL REFERENCE

| Number | Name          | Used for                       |
| ------ | ------------- | ------------------------------ |
| 0      | read          | Read keyboard bytes            |
| 1      | write         | Write to terminal              |
| 7      | poll          | Non-blocking input check       |
| 13     | rt_sigaction  | Install signal handlers        |
| 15     | rt_sigreturn  | Signal return trampoline       |
| 16     | ioctl         | Terminal raw mode, window size |
| 35     | nanosleep     | Frame sleep                    |
| 60     | exit          | Clean shutdown                 |
| 228    | clock_gettime | Frame timing                   |

File descriptors: `0` = stdin, `1` = stdout, `2` = stderr.

---

## MODULE STRUCTURE

```text
baremetal/
├── src/
│   ├── core/
│   │   ├── entry.asm         ; _start, game loop, shutdown
│   │   └── game.asm          ; world map, player, DDA raycaster, enemies, doors, lighting
│   ├── platform/
│   │   ├── terminal.asm      ; raw mode, alt screen, signal handlers, window size
│   │   ├── input.asm         ; poll + read drain loop, key state flags
│   │   └── timing.asm        ; clock_gettime, elapsed, nanosleep
│   ├── math/
│   │   └── math.asm          ; sin/cos LUTs (×1024, 360 entries), Q8 helpers, int_to_ascii
│   └── render/
│       ├── render.asm        ; frame buffer, raycaster projection, sprites, gun HUD, game over
│       ├── render_data.asm   ; all data: colors, sprites, fonts, HUD strings
│       ├── render_utils.asm  ; buffer helpers, cursor moves, pixel sprite drawing
│       └── render_start.asm  ; start screen pixel-art rendering
├── Makefile
├── LICENSE                   ; GPLv3
├── README.md
└── TECHNICAL.md              ; this file
```

Cross-module linkage is `global`/`extern` only. No shared headers: symbol names are the ABI.

---

## MODULE DETAILS

### entry.asm

- `_start`: `init_terminal` → `get_terminal_size` → `init_game` → `render_init` → `render_start_screen` → game loop → `shutdown`
- **Game loop** (fixed 60fps timestep):
    1. `get_time(time_start)`
    2. `process_input`
    3. `quit_flag`? → shutdown
    4. `toggle_door` if `key_use`
    5. Handle `resize_flag` → `get_terminal_size` + `render_init`
    6. `update_game` (movement, enemies, shooting, lights)
    7. `render_frame`
    8. `get_time(time_current)`
    9. `elapsed_ns(time_start, time_current)`
    10. If under `FRAME_NS` budget: `sleep_remaining(budget - elapsed)`
    11. Loop
- `shutdown`: `restore_terminal` → `exit(0)`

### terminal.asm

**init_terminal:**

1. Save original `termios` via `ioctl(TCGETS)`
2. Build raw mode: clear `BRKINT | ICRNL | INPCK | ISTRIP | IXON` from `c_iflag`, `OPOST` from `c_oflag`, `ECHO | ICANON | IEXTEN | ISIG` from `c_lflag`, set `VMIN=0 VTIME=0`
3. Apply via `ioctl(TCSETS)`
4. Enter alternate screen buffer: `ESC[?1049h`
5. Hide cursor: `ESC[?25l`
6. Initial clear: `ESC[2J`
7. Install signal handlers for `SIGINT(2)`, `SIGTERM(15)`, `SIGSEGV(11)`, `SIGWINCH(28)` via `rt_sigaction`

**restore_terminal:**

1. Restore saved `termios` via `ioctl(TCSETS)`
2. Leave alternate screen: `ESC[?1049l`
3. Show cursor: `ESC[?25h`
4. Reset colours: `ESC[0m`

**get_terminal_size:** `ioctl(TIOCGWINSZ)` → `term_rows`, `term_cols`. Falls back to 80×24 if zero. Column count is decremented by 1 as a safety margin for escape-sequence wrapping.

**signal_handler:** Calls `restore_terminal`, then `exit(1)`. Ensures terminal is always left in usable state even on crash or Ctrl+C.

**resize_handler:** Sets `resize_flag` byte to 1. Consumed in game loop.

**restorer_trampoline:** Calls `rt_sigreturn` (syscall 15). Required by the kernel's `rt_sigaction` ABI on x86-64.

**Key structs:**

```nasm
termios (60 bytes, kernel layout):
  c_iflag   offset 0   (4 bytes)
  c_oflag   offset 4   (4 bytes)
  c_cflag   offset 8   (4 bytes)
  c_lflag   offset 12  (4 bytes)
  c_line    offset 16  (1 byte)
  c_cc[19]  offset 17  (19 bytes)
  → VTIME = c_cc[5] = offset 22
  → VMIN  = c_cc[6] = offset 23

sigaction (32 bytes, kernel layout):
  sa_handler   offset 0   (8 bytes)
  sa_flags     offset 8   (8 bytes)   ← SA_RESTORER required
  sa_restorer  offset 16  (8 bytes)
  sa_mask      offset 24  (8 bytes)
```

### input.asm

**Model:** last key wins per axis, no diagonals.

**process_input:**

1. Clear all direction flags, `key_use`, `any_key`
2. Drain all bytes from stdin via `poll(timeout=0)` + `read(1 byte)` loop
3. Each recognised key (`w/a/s/d/e/q/ `, case-insensitive) sets its flag
4. W cancels S, S cancels W, A cancels D, D cancels A (same axis)
5. Non-opposing pairs (W+D, S+A) can coexist for tank controls
6. Last byte on each axis wins independently within the drain

**Exported flags:** `key_up`, `key_down`, `key_left`, `key_right`, `key_use`, `key_shoot`, `quit_flag`, `any_key` (each 1 byte, 0 or 1).

### timing.asm

**get_time(rdi=timespec_ptr):** `clock_gettime(CLOCK_MONOTONIC, ptr)`

**elapsed_ns(rdi=start, rsi=end):** Returns nanoseconds in `rax`.

```text
elapsed = (end.tv_sec - start.tv_sec) * 1_000_000_000
        + (end.tv_nsec - start.tv_nsec)
```

**sleep_remaining(rdi=ns):** Frame sleeps are always < 1s, so:

```nasm
time_sleep.tv_sec  = 0
time_sleep.tv_nsec = rdi
nanosleep(&time_sleep, NULL)
```

### math.asm

**int_to_ascii(rax=value, rdi=dest):** Converts unsigned integer to ASCII decimal.

- Digits computed in reverse via repeated `div 10`, stored in `digit_buf`
- Written forward to destination
- Returns: `rdi` advanced past last byte, `rax` = bytes written
- Preserves `rbx`, `r12`–`r15` (callee-saved per SysV ABI)
- Special case: value 0 writes `'0'` directly

**lut_mul(rdi=Q8, rsi=LUT_val):** `(rdi × rsi) >> 10`. Returns Q8.

**fp_div(rdi, rsi):** `(rdi << 8) / rsi`. Used for DDA `delta_dist`.

**abs_val(rdi):** Branchless absolute value via `cqo` / `xor` / `sub`.

**LUTs:** 360-entry sin/cos tables at ×1024 scale. Accessed as `[table + angle*8]`. ×1024 eliminates wall-height stair-stepping visible with ×256 at 24+ rows.

### game.asm

**Player state:**

```nasm
player_x:     resq 1    ; Q8 fixed-point X
player_y:     resq 1    ; Q8 fixed-point Y
player_angle: resq 1    ; 0..359 degrees (direct LUT index)
player_health: resq 1   ; 0..100
game_over_flag: resq 1  ; 0=playing, 1=dead
```

**init_game:** Player spawns at `(15<<8)|128` on both axes (cell 15,15, subcell 0.5), angle 0 (east), 100 HP. The non-integer start prevents `side_dist = 0` at first grid boundary in the DDA.

**World map:** 32×32 row-major byte array, `world_map[row * 32 + col]`. Values: 0=open, 1=stone, 2=brick, 3=metal, 4=wood, 5=door. Four quadrants separated by central cross-corridor at rows/cols 15–16. Parallel `door_state` array tracks open/closed per cell.

**update_game:**

1. Check game_over_flag and skip input if dead
2. Rotate left/right (±ROT_SPEED=5°, wrapped to 0..359)
3. Compute forward/backward movement:
    - `dx = (cos[angle] × MOVE_SPEED) >> 10` (Q8)
    - `dy = (sin[angle] × MOVE_SPEED) >> 10` (Q8)
    - MOVE_SPEED = 16 (Q8) → ~3.75 cells/sec at 60fps
    - If S pressed (no W): negate dx, dy
    - If both W+S: cancel (no move)
4. Wall sliding: test X move with current map_y, commit if passable. Then test Y move with possibly-updated map_x, commit if passable.
5. `is_passable(rax=cell_index)`: checks world_map for 0 (open) or 5+door_state open. Returns 0=blocked, 1=passable.
6. Shooting: hitscan via Z-buffer center distance. For each enemy: compute dot product (in front?) and cross product (in crosshair?). If `abs(cross) < 64` and `dot < wall_dist`, hit.
7. Decrement `gun_fire_timer`. Update muzzle flash light position/intensity.
8. Update pulsing light toggle.
9. Call `update_enemies`.

**cast_ray(rdi=angle) → rax=dist, rdx=wall_type, rcx=side:**

- Full DDA implementation with perpendicular distance projection.
- `delta_dist_x/y = |1048576 / ray_dir_x/y|` (1024² in Q8 math). Zero component → `DDA_INF (0x3FFFFFFFFFFFFFFF)`.
- Initial `side_dist` from Q8 fractional position.
- DDA loop: compare side_dist_x/y, step smaller axis, increment map coordinate, check world_map. Open cells loop. Door cells check door_state. Wall hit returns `perp_dist = side_dist_at_hit - delta_dist`.
- 64 max iterations (safety; perimeter walls guarantee earlier hit on 32×32 map).

**update_enemies:**

- 2 enemies, each with x/y (Q8), state, health, timer, sprite index.
- State machine: 0=Inactive, 1=Chase, 2=Hurt, 3=Dead.
- Chase: if player within 16-cell Manhattan distance, move toward player at speed 4 (Q8) with pathfinding via `is_passable`.
- Attack: if within ~0.75 cells, deal 10 damage every 32 frames.
- Hurt: on hit, stun for 10 frames, then return to Chase.
- Dead: sprite type changes to corpse (scale_y = 64, lying flat).
- Enemy positions synced to sprite array each frame for rendering.

**Lighting data (3 lights):**

```
light_x/y:   Q8 positions
light_r:     radius² (in 256-units) to avoid sqrt
light_i:     intensity (0=off, higher=brighter)
light_type:  0=static white, 1=pulsing red, 2=muzzle flash
```

Light 0: static at corridor center (16,16), intensity 4.
Light 1: pulsing in NW brick room (5,5), toggles 1↔6 every 16 frames.
Light 2: attached to player position, intensity 10 during muzzle flash (first 4 frames of 8-frame cycle).

### render.asm

**Frame buffer strategy:** Single buffer (256KB). `buf_pos` is write head. Frame starts with `ESC[H` (cursor home) + `ESC[?2026h` (sync begin), ends with `ESC[?2026l` (sync end) + `write(1, frame_buffer, len)`. The sync markers allow xterm.js to atomically paint the entire frame with no tearing.

**clear_buffer:** Reset `buf_pos` to start of `frame_buffer`, write cursor home + sync start.

**flush_buffer:** Append sync end marker, then single `write(1)` syscall.

**render_frame** runs in these stages:

**Stage 1: Raycast (Pass 1):**
For each column `c` (0..render_scr_cols-1):

1. Compute ray angle: `player_angle - 30 + c × 60 / (screen_cols - 1)`, normalised to [0,359]
2. `call cast_ray` → perpendicular distance, wall type, side
3. Save to Z-buffer: `z_buffer[c] = dist`
4. Compute U-coordinate (0..255) from hit position fraction for procedural texturing
5. Compute wall height: `(screen_rows × 1024) / dist`, capped at screen_rows
6. Compute wall top/bot: centred vertically
7. Select shade block (`█▓▒░`) by distance thresholds (2/4/8 cells)
8. Select color tier (0-3) by distance
9. Apply point lights: check hit point against each light's radius²; max intensity reduces tier by `intensity / 2`, clamped to 0
10. Store `col_char[c]`, `col_color[c]`, `col_top[c]` (word), `col_bot[c]` (word), `col_wall_type[c]`

**Stage 2: Render (Pass 2, row-major):**
For each row `r` (0..render_scr_rows-1):

1. `append_cursor_move(r+2, 2)` move to interior start
2. Emit color reset to prevent bleed
3. Compute floor band (0=horizon, 1=mid, 2=near) based on distance from screen center. Muzzle flash forces band 2.
4. For each column `c` (0..render_scr_cols-1):
    - If `r < col_top[c]`: ceiling. Procedural star field (hash of row×col → `▪`/`.`/` `)
    - If `r > col_bot[c]`: floor. Carpet texture (`▒`) with band-based color
    - Else: wall. Compute V-coordinate (0..255). Emit wall-type color escape (5 types × 4 tiers, reduced by light). Run procedural shader to select shade block (█▓▒░). Minimap zone replaces raycaster output for top-right 16×16 area.

**Procedural wall shaders:**

- Stone (type 1): solid block with 32-cell edge border (▓ border, █ centre)
- Brick (type 2): Wolfenstein staggered, 16-cell horizontal/vertical mortar gaps, alternating row offset
- Metal (type 3): XOR grate pattern (every 64 cells XOR toggles █↔▓)
- Wood (type 4): vertical panel strips (32-cell period, 8-cell dark band)
- Door (type 5): panel with centre lock band (thick horizontal bar), 24-cell border

**Stage 3: Minimap:**
16×16 scrolling viewport into world map. Top-right of screen. `#` for walls, `.` for open, `+` for closed doors, `>v<^` for player direction marker. Viewport follows player, clamped at map edges (0..16 offset range on a 32×32 map).

**Stage 4: Sprites (Painter's Algorithm):**
8 sprites (barrel×2, pillar×2, key×2, enemy×2). Each frame:

1. Compute camera-space transform for each active sprite:
    - `trans_y = (dx·cos + dy·sin) >> 8` (depth in front)
    - `trans_x = (-dx·sin + dy·cos) >> 8` (lateral offset)
    - If `trans_y <= 0`: skip (behind player)
2. Sort by `trans_y` descending (bubble sort, 8 elements)
3. For each sprite in sorted order:
    - Project to screen: `sprite_screen_x = center_col + (trans_x × proj_coeff) / trans_y`
    - Scale: `base_h = (screen_rows × 1024) / trans_y`, then apply per-type Q8 scale factors
    - Compute bounding box, clamp to screen
    - Emit per-type color escape once
    - For each pixel in bounding box, check Z-buffer, compute UV, run shader:
        - Barrel: rounded drum with horizontal bands
        - Pillar: cylinder with edge shading
        - Key: diamond shape
        - Enemy: circle with eye cutout
        - Corpse: darker oval, flat aspect ratio

**Stage 5: Gun HUD:**
After sprites, before HUD. Fixed screen-space position at bottom centre.

1. If `gun_fire_timer > 4`: draw muzzle flash (yellow, 24×6) above pistol
2. Draw pistol (blue-grey, 24×9) at bottom-centre
3. Draw hand (skin-tone, 24×8) below pistol
4. Recoil: shift gun down 1 row during fire

**Stage 6: Game Over:**
If `game_over_flag == 1`: wipe buffer, fill entire screen area with red background (`ESC[41m`), center pixel-font "GAME OVER" in black, center "[ PRESS Q TO QUIT ]" in yellow. Fall through to HUD.

**Stage 7: HUD:**
Bottom row (row = `term_rows`): `FPS:##  POS:##,##  ANG:###  HP:###` followed by "GAME OVER" if dead.

---

## BUILD

```bash
make          # build ./baremetal
make run      # build and run
make clean    # remove *.o and binary
```

Makefile flags: `nasm -f elf64 -g -F dwarf -I src/render/` (DWARF debug symbols, include path for render includes), `ld -static`. Auto-dependency generation via `-MD` with `.d` file include.

---

## Feature Inventory

| Feature                                    | Location                  |
| ------------------------------------------ | ------------------------- |
| Fixed 60fps timestep loop                  | `entry.asm`               |
| Terminal raw mode (full flags)             | `terminal.asm`            |
| Alternate screen buffer                    | `terminal.asm`            |
| Signal handlers (SIGINT/TERM/SEGV/WINCH)   | `terminal.asm`            |
| Dynamic terminal size via TIOCGWINSZ       | `terminal.asm`            |
| No-flicker frame buffer with sync markers  | `render.asm`              |
| Non-blocking input with poll+read drain    | `input.asm`               |
| Grid-native input (no diagonals)           | `input.asm`               |
| Box-drawing border                         | `render.asm`              |
| 32×32 world map, 4 quadrants, 5 wall types | `game.asm`                |
| DDA raycaster with perpendicular distance  | `game.asm`                |
| Procedural wall texturing (5 types)        | `render.asm`              |
| 4-tier distance shading (█▓▒░)             | `render.asm`              |
| Colour escapes per wall type (5×4=20)      | `render_data.asm`         |
| Ceiling star field                         | `render.asm`              |
| Floor carpet with band shading             | `render.asm`              |
| 3-point dynamic lighting                   | `game.asm` + `render.asm` |
| Interactive doors (E key toggle)           | `game.asm`                |
| Wall sliding collision                     | `game.asm`                |
| Sprite system (8 sprites, 4 types)         | `render.asm`              |
| Painter's Algorithm depth sorting          | `render.asm`              |
| Z-buffer for sprite occlusion              | `render.asm`              |
| Scrolling minimap with direction marker    | `render.asm`              |
| Enemy AI (chase/attack/hurt/dead)          | `game.asm`                |
| Hitscan combat (dot/cross product)         | `game.asm`                |
| Gun HUD (pistol + hand + muzzle flash)     | `render.asm`              |
| Pixel-art start screen                     | `render_start.asm`        |
| Game over screen                           | `render.asm`              |
| FPS counter (60-frame rolling)             | `render.asm`              |
| Fixed-point sin/cos LUTs (×1024, 360°)     | `math.asm`                |
| int_to_ascii with correct ABI              | `math.asm`                |

---

## WHY AUDIO WAS DROPPED

The game is silent by design. Here is the analysis:

### Paths Considered

| Approach                                                                   | Permissions Requirement                 | Verdict                                                        |
| -------------------------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| `ioperm(0x42, 3, 1)` + `outb` to PIT channels 2 and system port 0x61       | Root/sudo (`CAP_SYS_RAWIO`)             | Fails: requires sudo for a web demo                            |
| ALSA `open("/dev/snd/pcmC0D0p")` + `ioctl` + `write` PCM frames            | `audio` group membership                | Fails: violates zero-dependency thesis                         |
| Write byte `0x07` to stdout; terminal plays system bell                    | None                                    | Browsers block by default, ttyd needs `-t enableBell=true`     |
| Synthesize waveforms in assembly, write raw PCM to stdout, pipe to `aplay` | `aplay` needs audio on playback machine | No ttyd real-time feedback; possible as a post-hoc `.wav` dump |
| JavaScript wrapper around ttyd reads audio events, plays via browser       | None                                    | reliable web audio path, but it is a JS project                |

### The Honest Trade-off

A DSP engine in assembly (ADSR envelopes, square/saw/noise oscillators, ring buffer mixer) is technically feasible. I have already written one in Rust and TypeScript for other engines. The math ports easily. The output path does not.

Rather than fight terminal limitations for audio that no visitor will hear reliably, the silence won. Sound is deferred until either:

- A clear cross-platform audio output emerges for web terminals (unlikely to change in the near term), or
- A companion web page with Web Audio API synthesis is built as a separate wrapper (a JavaScript project, not an assembly one).

---

## No Linear Frame Buffer

I attempted to build a 2D row-major character array in memory (LFB) to eliminate escape codes in the hot path, and flickeing on the web ttyd output. However:

- Buffering into an intermediate 2D grid matrix and then translating it back to ANSI escapes at the end of the frame actually hurt memory throughput and caused cache thrashing.
- Terminals natively consume streams of bytes, so appending directly to the `buf_pos` stream is fundamentally faster.
- It forced all simple text rendering (HUD, Start Screen, Editor, Raycaster) to adopt a complex, pixel-by-pixel grid placement with manual color indexing.
- It broke the simplicity of raw ANSI string manipulation.
- Currently, I write one ANSI escape sequence per cell change. The LFB writes, then serialises the entire grid. For a typical frame where only a few cells change, the LFB does 8× more work.
- The engine already runs fast. The LFB caused endless bugs (segfaults, flicker regressions, overlay overwrites) for zero tangible gameplay benefit.
- The existing ANSI cursor-move approach already renders flicker-free on real terminals with the existing sync markers (`ESC[?2026h`).

---

## PITFALLS & NOTES

**Register clobbering**: Assembly has no variable names. Every function shares registers. Push/pop callee-saved registers (`rbx`, `r12`–`r15`) at function entry/exit. `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`–`r11` are caller-saved: assume destroyed after any call.

**1-indexed terminal coordinates**: `ESC[row;colH` is 1-indexed. Player position is stored 1-indexed. Border is at row/col 1 and row/col `term_rows`/`term_cols`. Playable interior is `[2, term_cols-1]` × `[2, term_rows-1]`.

**UTF-8 block characters are 3 bytes**: `█` = `0xE2 0x96 0x88`. Write 3 bytes. When computing cursor column positions after drawing it, the terminal counts it as 1 column (it's a single-width character). Don't conflate byte count with display width.

**`nanosleep` can be interrupted**: A signal during `nanosleep` returns early (`EINTR`). For a game loop this is fine: just run the next frame early.

**Alternate screen requires cursor-home not clear**: After `ESC[?1049h` puts you in the alt screen, use `ESC[H` (cursor home) to start each frame. Don't use `ESC[2J` per frame: the alt screen starts blank and cursor-home overwrites in place with no flash.

**Terminal cleanup on crash**: Signal handlers for `SIGINT`/`SIGTERM`/`SIGSEGV` call `restore_terminal` before exit. If the terminal gets stuck anyway (e.g. `SIGKILL`), run `reset` to recover.

**Synchronized output**: `ESC[?2026h` / `ESC[?2026l` (DEC private mode 2026) enables atomic updates on xterm.js. The terminal buffers all output between the begin/end markers and paints the entire frame at once, eliminating tearing.

**The lighting system was premature.** The lighting adds complexity to the wall shading path (checking 3 lights per column) without enemies or gameplay to benefit from it yet. It's not broken, but it was out of sequence.

**The `term_cols - 1` hack in terminal.asm** is a workaround for an escape-sequence wrapping bug, not a proper fix. The real issue is that the renderer doesn't account for the byte-width of escape codes when computing column positions. This will bite you again if you add more color complexity.

---

## GDB workflow

```bash
gdb ./baremetal
(gdb) layout asm           # assembly view
(gdb) layout regs          # register view
(gdb) b render_frame       # breakpoint by symbol name
(gdb) si                   # step one instruction
(gdb) x/32xb &world_map    # examine memory as hex bytes
(gdb) x/gd &player_x       # read Q8 value
```

---

## REFERENCE

| Resource                     | URL                                                                      |
| ---------------------------- | ------------------------------------------------------------------------ |
| x86-64 instruction reference | felixcloutier.com/x86                                                    |
| Linux syscall table          | chromium.googlesource.com/chromiumos/docs/+/master/constants/syscalls.md |
| NASM documentation           | nasm.us/doc                                                              |
| Terminal escape codes        | invisible-island.net/xterm/ctlseqs/ctlseqs.html                          |
| termios struct               | `man 3 termios`                                                          |

---
