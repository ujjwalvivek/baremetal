# BAREMETAL

![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=x86-64&rightText=assembly&badgeColor=808000&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=Linux+only&rightText=Static+binary&badgeColor=804000&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=Intel+syntax&badgeColor=004080&textColor=ffffff)
![Echopoint SVG](https://echopoint.ujjwalvivek.com/svg/badges/custom?leftText=16KB+code&rightText=128KB+data%2Bbss&badgeColor=400040&textColor=ffffff)

## Constraints

Entry point is `_start`. No malloc, printf, memcpy. Every syscall is a raw `syscall` instruction. All memory is statically allocated in `.data` or `.bss`: sizes fixed at link time. The FPU is never touched; trigonometry runs on integer registers via LUTs and Q8 fixed-point. One `write(1, buf, len)` per frame: no per-character writes, no ioctl inside the render path.

## Build

```bash
nasm -f elf64 -g -F dwarf <file>.asm -o <file>.o
ld -static -o baremetal entry.o terminal.o render.o input.o timing.o math.o game.o
```

DWARF is on by default. Stripped for production. Link order doesn't matter here but the Makefile preserves it for readability.

---

## Module Map

```nasm
entry.asm      ;_start, fixed-timestep game loop, shutdown
terminal.asm   ;termios raw mode, alternate screen, TIOCGWINSZ, signal handlers
render.asm     ;frame buffer, raycaster projection, minimap, flush
input.asm      ;poll+read drain loop, key state flags
timing.asm     ;clock_gettime(CLOCK_MONOTONIC), elapsed_ns, nanosleep
math.asm       ;sin/cos LUTs (×1024, 360 entries), Q8 helpers, int_to_ascii
game.asm       ;world map, player state, DDA raycaster, update_game
```

Cross-module linkage is `global`/`extern` only. No shared headers: symbol names are the ABI.

## Game Loop

Fixed 60fps timestep. `FRAME_NS = 16666666`.

```nasm
init_terminal → get_terminal_size → init_game → render_init → loop:
  get_time(time_start)
  process_input
  quit_flag? → shutdown
  update_game
  render_frame
  get_time(time_current)
  elapsed = elapsed_ns(time_start, time_current)
  if FRAME_NS - elapsed > 0: sleep_remaining(FRAME_NS - elapsed)
```

`nanosleep` woken by a signal returns early with `EINTR`. The loop doesn't retry: it just runs the next frame. At 60fps the drift is imperceptible.

## Terminal (`terminal.asm`)

Init: `ioctl(TCGETS)` to save termios, then modify in place: clear `ICANON | ECHO | ISIG | IEXTEN` from `c_lflag`, `OPOST` from `c_oflag`, `BRKINT | ICRNL | INPCK | ISTRIP | IXON` from `c_iflag`, set `VMIN=0 VTIME=0`. Apply via `ioctl(TCSETS)`. Then `ESC[?1049h` (alternate screen), `ESC[?25l` (hide cursor), `ESC[2J` (clear once). Signal handlers last.

Restore: `ioctl(TCSETS)` with the saved struct, `ESC[?1049l`, `ESC[?25h`, `ESC[0m`.

`SIGINT`, `SIGTERM`, `SIGSEGV` all call `restore_terminal` then `exit(1)`. The signal handler's `sa_flags` must include `SA_RESTORER` and `sa_restorer` must point to a trampoline that calls `rt_sigreturn` (syscall 15). The kernel requires this on x86-64. Leave it out and you get SIGSEGV on signal return.

`get_terminal_size`: `ioctl(TIOCGWINSZ)`. Falls back to 80×24 if either dimension is zero.

The kernel `termios` struct layout: not glibc's, which differs:

```nasm
 0: c_iflag  (4 bytes)
 4: c_oflag  (4 bytes)
 8: c_cflag  (4 bytes)
12: c_lflag  (4 bytes)
16: c_line   (1 byte)
17: c_cc[19]: VTIME at [5] (offset 22), VMIN at [6] (offset 23)
```

## Fixed-Point

Q8: real value encoded as `real × 256`. Integer part in bits 63..8, fraction in 7..0. Addition and subtraction work directly on the encoded values. To get the map cell index: `sar rax, 8`.

The LUTs are scaled ×1024, not ×256. After a LUT multiply, shift right by 10:

```nasm
imul rax, [cos_table + rdi*8]
sar  rax, 10                    ; Q8 result
```

The scale matters: ×256 gives 256 discrete sine values, which produces visible stair-stepping in wall heights at typical screen sizes. ×1024 is enough resolution that the quantization is below the display threshold.

## Math (`math.asm`)

`sin_table` / `cos_table`: 360 × `dq` in `.data`, precomputed as `round(sin/cos(i°) × 1024)`. ~5.6KB total. Index as `[table + angle*8]`.

`int_to_ascii(rax=value, rdi=dest)`: divide-by-10 loop into `digit_buf`, write forward. Returns `rdi` past last byte, `rax` = byte count. Preserves `rbx`, `r12`–`r15`. Zero handled as a special case before the loop.

`lut_mul(rdi=Q8, rsi=LUT_val)`: `(rdi × rsi) >> 10`. Returns Q8.

`fp_div(rdi, rsi)`: `(rdi << 8) / rsi`. Used to compute `delta_dist` in DDA setup.

`abs_val(rdi)`: branchless via `cqo` / `xor` / `sub`.

## Input (`input.asm`)

Each frame: zero all four direction flags, drain stdin with `poll(timeout=0)` + `read(1 byte)` until poll returns 0. Each recognised byte sets its flag and clears only its axis-opposite: W clears S, A clears D, and vice versa. Non-opposing pairs (W+D, W+A) both set. The terminal sends held keys as repeated bytes in the buffer; last byte on each axis wins within the drain, independent of the other axis. `quit_flag` just gets set and is never cleared.

## World Map (`game.asm`)

256-byte array, row-major, 0=open 1=wall, `MAP_WIDTH = MAP_HEIGHT = 16`. Four rooms (NW/NE/SW/SE) connected by an E-W corridor (rows 7–8) and a N-S corridor (cols 7–8). Outer perimeter is solid. Doorways at col 3 and col 12 in the dividing walls at rows 6 and 9.

Player spawns at `(7<<8)|128` on both axes: map cell (7,7), fractional offset 0.5, center of the corridor, facing east. The non-integer start position matters: a player exactly on a grid line with an adjacent wall produces `side_dist = 0`, which collapses `perp_dist` to 0 and causes a divide-by-zero in the projection.

Cell lookup: `world_map[map_y * 16 + map_x]`.

## DDA Raycaster (`game.asm: cast_ray`)

```nasm
in:  rdi = ray angle (0..359)
out: rax = perpendicular wall distance (map units × 1024), min 1
```

`delta_dist_x/y = |1024² / ray_dir_x/y|`: the distance along the ray between consecutive vertical or horizontal grid crossings. When a ray direction component is zero, the corresponding delta is set to `DDA_INF (0x3FFFFFFFFFFFFFFF)` so that axis is never stepped.

Initial `side_dist` is computed from the fractional part of the Q8 player position: how far the ray travels from the player's subgrid offset to the first grid boundary on each axis. For a ray moving in the negative direction: `(frac × delta) >> 8`. Positive: `((256 - frac) × delta) >> 8`.

The loop compares `side_dist_x` vs `side_dist_y`, steps the smaller, increments the corresponding map coordinate, checks `world_map`. Max 32 iterations: sufficient for a 16×16 map with solid perimeter.

The perpendicular distance: `side_dist_at_hit - delta_dist`. This is the distance to the grid line that was just crossed, measured perpendicular to the view plane: not the Euclidean distance to the hit point. It directly cancels the fisheye distortion. No separate cosine correction needed.

Wall collision in `update_game` tests X and Y independently: proposed `new_x` checked with current `map_y`, proposed `new_y` checked with the (possibly already updated) `map_x`. Both axes can move in the same frame. That's wall sliding.

## Render (`render.asm`)

128KB static frame buffer. `buf_pos` is the write head. Single `write(1, frame_buffer, buf_pos - frame_buffer)` at end of frame.

`clear_buffer`: resets `buf_pos`, writes `ESC[H`. Cursor home, not clear: the alt screen overwrites in place, no blank flash.

`render_init`: draws the box border and blanks the interior. Called once at startup.

`render_frame` runs in two passes.

**Pass 1**: at entry, compute `render_scr_cols = min(term_cols - 2, 512)` and `render_scr_rows = min(term_rows - 2, 200)`. These drive every loop bound in this frame. For each column `c`:

```
angle  = player_angle - 30 + (c × 60 / (render_scr_cols - 1)), normalised to [0,359]
dist   = cast_ray(angle)
wall_h = (render_scr_rows × 1024) / dist, capped at render_scr_rows
top    = (render_scr_rows - wall_h) / 2
bot    = top + wall_h - 1
shade  = dist < 2048 → 0x88 (█) | < 4096 → 0x93 (▓) | < 8192 → 0x92 (▒) | else → 0x91 (░)
```

Results go into `col_char[c]`, `col_top[c]`, `col_bot[c]`: 512-byte `.bss` arrays.

**Pass 2**: row-major. Per row: `append_cursor_move(r+2, 2)`, then per column: space if above `col_top`, `.` if below `col_bot`, `0xE2 0x96 <col_char[c]>` (3-byte UTF-8 block) if inside. The 3 buffer bytes encode 1 terminal column: don't conflate byte offsets with display positions.

`render_minimap`: runs after Pass 2, before flush. Writes 16×16 ASCII into columns `[term_cols - 16, term_cols - 1]`, rows 2–17. `#` / `.` / `@` (player at `player_x >> 8`, `player_y >> 8`). Overwrites whatever the raycaster put there.

`append_cursor_move(rdi=row, rsi=col)`: emits `ESC[<row>;<col>H` using `int_to_ascii`. Preserves `rbx`, `r12`, `r13`.

## Timing (`timing.asm`)

`clock_gettime(CLOCK_MONOTONIC)` writes a 16-byte `timespec`. `elapsed_ns` is `(Δsec × 1e9) + Δnsec`. Frame sleep is `nanosleep` with `tv_sec=0` and the nanosecond remainder in `tv_nsec`. The struct is `{tv_sec at 0, tv_nsec at 8}`: putting the nanosecond value in `tv_sec` by accident gives a ~16 million second sleep.

## ABI

SysV x86-64. `rbx`, `rbp`, `r12`–`r15` are callee-saved: push/pop at function entry/exit if used. Everything else is caller-saved; assume it's destroyed after any call. Clobbering a callee-saved register without saving it won't crash immediately: it corrupts whatever the caller stored there, and you'll spend an hour in GDB before tracing it back.

Stack is 16-byte aligned before `call`. The return address push leaves it misaligned by 8 on function entry. Functions that call other functions and haven't pushed an odd number of 8-byte values need `sub rsp, 8` to re-align before the first nested call.

Signal handlers run on the same stack. The red zone below `rsp` is not safe to use.

## Known Issues

`col_top` and `col_bot` are single bytes. Values above 255 truncate silently. `MAX_SCREEN_ROWS` is capped at 200, so this doesn't bite in practice.

Angle normalisation does one add or subtract. If `ROT_SPEED` were ever >= 360 this would wrap incorrectly: it's 5, so it won't.

SIGWINCH is not handled. Resize after startup corrupts the border until restart.

DDA iteration cap is 32. Fine for a 16×16 map. Raise it if the map grows past `MAP_WIDTH + MAP_HEIGHT > 32`.

## Debugging

```bash
gdb ./baremetal
(gdb) layout asm
(gdb) layout regs
(gdb) b cast_ray
(gdb) b render_frame
(gdb) si
(gdb) x/16xb &world_map
(gdb) x/gd &player_x            # raw Q8 value
(gdb) p *(long*)&player_x >> 8  # map cell
```

Terminal stuck in raw mode after a crash: `reset`.
