TARGET ?= ferris
MODULES ?= ferris
OBJS ?= $(addprefix obj/, $(addsuffix .o, $(MODULES)))

CA65	?= ca65
LD65	?= ld65

CA65FLAGS	?= -g --cpu 65C02 --feature string_escapes
LD65FLAGS	?= -C config.cfg -m $(TARGET).map -Ln $(TARGET).lbl

all: $(TARGET).bin

$(TARGET).bin: $(OBJS)
	$(LD65) $(LD65FLAGS) -o $@ $^

obj/%.o: *.asm
	@mkdir -p obj
	$(CA65) $(CA65FLAGS) $< -o $@


clean: 
	rm -rf obj $(TARGET).bin $(TARGET).map $(TARGET).lbl

.PHONY: all clean
	
