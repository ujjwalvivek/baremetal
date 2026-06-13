ASM      = nasm
ASMFLAGS = -f elf64 -g -F dwarf -I src/render/
LD       = ld
LDFLAGS  = -static

SRCS = src/core/entry.asm src/platform/terminal.asm src/render/render.asm \
       src/platform/input.asm src/platform/timing.asm src/math/math.asm \
       src/core/game.asm
OBJS = $(SRCS:.asm=.o)
TARGET = baremetal

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.asm
	$(ASM) $(ASMFLAGS) $< -o $@

# render.asm includes render_data.asm, render_utils.asm, render_start.asm
src/render/render.o: src/render/render.asm src/render/render_data.asm \
                     src/render/render_utils.asm src/render/render_start.asm

clean:
	rm -f $(OBJS) $(TARGET)

run: $(TARGET)
	./$(TARGET)
