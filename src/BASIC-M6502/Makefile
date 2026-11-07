# ca65/ld65 build of the original Apple configuration (REALIO=4).
CA65 ?= ca65
LD65 ?= ld65
PYTHON ?= python3
CA65FLAGS ?= -g --cpu 6502
LD65FLAGS ?=

.PHONY: all m6502 imnotwopr assemble regen check check-imnotwopr clean
all: m6502.bin m6502-lowram.bin m6502.map m6502.lbl
m6502: all
imnotwopr: m6502-imnotwopr.bin m6502-imnotwopr.map m6502-imnotwopr.lbl
assemble: obj/m6502.o

obj/m6502.o: m6502.s imnotwopr_config.inc imnotwopr.inc
	@mkdir -p obj
	$(CA65) $(CA65FLAGS) -l obj/m6502.lst -o $@ $<

# ld65 writes all four outputs together (GNU make 4.3+ grouped targets).
m6502.bin m6502-lowram.bin m6502.map m6502.lbl &: obj/m6502.o config.cfg
	$(LD65) $(LD65FLAGS) -C config.cfg -m m6502.map -Ln m6502.lbl -o m6502.bin $<

obj/m6502-imnotwopr.o: m6502.s imnotwopr_config.inc imnotwopr.inc
	@mkdir -p obj
	$(CA65) $(CA65FLAGS) -D REALIO=6 -l obj/m6502-imnotwopr.lst -o $@ $<

m6502-imnotwopr.bin m6502-imnotwopr.map m6502-imnotwopr.lbl &: obj/m6502-imnotwopr.o imnotwopr.cfg
	$(LD65) $(LD65FLAGS) -C imnotwopr.cfg -m m6502-imnotwopr.map -Ln m6502-imnotwopr.lbl -o m6502-imnotwopr.bin $<

# Explicit: ordinary builds also allow hand-editing the converted source.
regen:
	$(PYTHON) convert.py

check: all imnotwopr
	$(PYTHON) -B test_conversion.py

JOSHUA ?= ../joshua/build/gcc14/joshua
check-imnotwopr: imnotwopr
	$(PYTHON) -B test_imnotwopr.py $(JOSHUA)

clean:
	rm -rf obj m6502.bin m6502-lowram.bin m6502.map m6502.lbl \
	       m6502-imnotwopr.bin m6502-imnotwopr.map m6502-imnotwopr.lbl
