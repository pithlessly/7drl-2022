PASCAL_SOURCES := $(wildcard src/*.pas)
PASCAL_BUILD := $(PASCAL_SOURCES:src/%=build/%)

.PHONY: run, compile
run: build/main
	$<
compile: build/main

build/main: $(PASCAL_BUILD) build/raw_mode.o
	cd build; fpc $(FPCOPTS) main.pas

build/%.pas: src/%.pas
	@mkdir -p build
	cp $< $@

build/%.o: src/%.c
	@mkdir -p build
	cc -c $< -o $@

.PHONY: clean
clean:
	rm -rf build
