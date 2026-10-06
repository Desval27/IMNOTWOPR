# -----------------------------------------------------------------------------
# ferrous
#
# Each name in TARGETS maps directly:
#
#     target1 -> target1.s -> target1.bin / target1.map / target1.lbl
#
# Additional assembled modules can be linked into an individual target with
# <target>_MODULES.  Textually included files (.include) can be listed in
# ASM_DEPS globally or <target>_DEPS for a particular target.
# -----------------------------------------------------------------------------

TARGETS := ferrous sysdiag

# -----------------------------------------------------------------------------
# Build Configuration
# -----------------------------------------------------------------------------
# Set to 1 to allow for text strings longer than 255 bytes.  
USE_EXTENDED_TEXT ?= 1
# Set to 1 to work around a bug in the ACIA that can cause it to miss characters when the CPU is running at full speed.  This is a crude way to do it, but it works for now.
ACIA_BUG ?= 1
# Set to a value that will give the ACIA time to send a character before the next one is sent.  This is a crude way to do it, but it works for now.
PRINT_CHR_DELAY ?= 255

CA65 ?= ca65
LD65 ?= ld65

CONFIG ?= config.cfg
INCLUDE_DIRS ?= -I . -I lib

DEFINES_LIST = USE_EXTENDED_TEXT ACIA_BUG PRINT_CHR_DELAY
CA65_DEFINES = $(foreach d,$(DEFINES_LIST),-D $(d)="$(value $(d))")

CA65FLAGS ?= -g --cpu 65C02 ${INCLUDE_DIRS} ${CA65_DEFINES} --feature string_escapes
LD65FLAGS ?= -C $(CONFIG)

# Optional modules assembled separately and linked with a target.
# Names are source paths without the .s suffix.
#
# COMMON_MODULES := lib/console lib/delay
# target1_MODULES := lib/uart
# target2_MODULES := lib/math
COMMON_MODULES := 
ferrous_MODULES :=
sysdiag_MODULES :=

# Files pulled in textually with ca65 .include directives.  Listing them here
# makes Make rebuild an example when one changes.  The wildcard is intentionally
# just a convenience; add other include directories/files as needed.
ASM_DEPS := $(wildcard *.inc lib/*.inc)

# Optional per-target textual dependencies, for example:
# target1_DEPS := lib/macros.inc lib/hardware.inc
# target2_DEPS := lib/macros.inc
ferrous_DEPS := 
sysdiag_DEPS :=


.PHONY: all clean $(TARGETS)

all: $(addsuffix .bin,$(TARGETS))

# Convenience targets: "make target1" builds target1.bin.
$(TARGETS): %: %.bin

# Build one linker rule per program.  Each program always starts with the
# same-named source/object, then adds any common and target-specific modules.
define PROGRAM_template
$1_OBJS := obj/$1.o \
           $$(addprefix obj/,$$(addsuffix .o,$$(COMMON_MODULES))) \
           $$(addprefix obj/,$$(addsuffix .o,$$($1_MODULES)))

obj/$1.o: $$($1_DEPS)

$1.bin: $$($1_OBJS) $$(CONFIG)
	$$(LD65) $$(LD65FLAGS) -m $1.map -Ln $1.lbl -o $$@ $$(filter %.o,$$^)
endef

$(foreach t,$(TARGETS),$(eval $(call PROGRAM_template,$(t))))

# True one-to-one assembly rule:
#     foo.s       -> obj/foo.o
#     lib/foo.s   -> obj/lib/foo.o
obj/%.o: %.s $(ASM_DEPS)
	@mkdir -p $(dir $@)
	$(CA65) $(CA65FLAGS) $< -o $@

clean:
	rm -rf obj \
	       $(addsuffix .bin,$(TARGETS)) \
	       $(addsuffix .map,$(TARGETS)) \
	       $(addsuffix .lbl,$(TARGETS))