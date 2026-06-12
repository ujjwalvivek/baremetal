ASM      = nasm
ASMFLAGS = -f elf64 -g -F dwarf -I src/render/
LD       = ld
LDFLAGS  = -static

SRCS = src/core/entry.asm src/platform/terminal.asm src/render/render.asm src/platform/input.asm src/platform/timing.asm src/math/math.asm src/core/game.asm
OBJS = $(SRCS:.asm=.o)
TARGET = baremetal

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.asm
	$(ASM) $(ASMFLAGS) $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

run: $(TARGET)
	./$(TARGET)
