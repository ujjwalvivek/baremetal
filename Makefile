ASM      = nasm
ASMFLAGS = -f elf64 -g -F dwarf
LD       = ld
LDFLAGS  = -static

SRCS = entry.asm terminal.asm render.asm input.asm timing.asm math.asm game.asm
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
