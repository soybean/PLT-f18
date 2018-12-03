# "make test" removes all previously generated files, compiles everything, and runs the regression tests

#.PHONY : test
#test : all test-script.sh
#	./test-script.sh

# "make all" removes all previously generated files and builds the executable

.PHONY : all
all : san clean bawk.native convert.o structure.o mylist.o

san:
	if [[ -f _build/sanitize.sh ]] ; then _build/sanitize.sh ; fi

# "make bawk.native" compiles the compiler

.PRECIOUS : bawk.native
bawk.native :
	opam config exec -- \
	ocamlbuild -use-ocamlfind -pkgs llvm,llvm.analysis -cflags -w,+a-4 \
		bawk.native

# "make clean" removes all generated files

.PHONY : clean
clean :
	ocamlbuild -clean
	#rm convert.o

.PHONY : convert
convert : convert.c cc -o convert convert.c

.PHONY : structure
structure : structure.c cc -o structure structure.c

.PHONY : array
array : mylist.c cc -o array mylist.c

.PHONY : cleantests
cleantests :
	rm tests/*.out tests/*.err
