VASM 		:= vasm6502_oldstyle
VASM_FLAGS 	:= -c02 -Fbin -dotdir
TARGETS		:= ferris.bin

all: $(TARGETS)

clean:
	@rm -f $(TARGETS)

%.bin: %.s
	$(VASM) $(VASM_FLAGS) $< -o $@

dump: ferris.bin
	@od -c -t x1 ferris.bin
