PASCAL_SOURCES := $(wildcard src/*.pas)
PASCAL_BUILD := $(PASCAL_SOURCES:src/%=build/%)

.PHONY: run, compile
compile: build/main
run: build/main
	$<

build/main: $(PASCAL_BUILD) build/raw_mode.o
	touch $(PASCAL_BUILD)
	cd build; fpc $(FPCOPTS) main.pas

build/%.pas: src/%.pas | build
	cp $< $@

build/%.o: src/%.c | build
	cc -c $< -o $@

build:
	mkdir -p build

.PHONY: clean
clean:
	rm -rf build
