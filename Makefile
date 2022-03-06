.PHONY: run, compile
run: build/main
	$<
compile: build/main

build/main: src/main.pas build/raw_mode.o
	cp $< build/main.pas
	cd build; fpc $(FPCOPTS) main.pas

build/raw_mode.o: src/raw_mode.c
	@mkdir -p build
	cc -c $< -o $@

.PHONY: clean
clean:
	rm -rf build
