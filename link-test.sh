set -e
./bawk.native -c tests/pass-config.bawk > int_to.ll
llc -relocation-model=pic int_to.ll > int_to.s
cc -o int_to.exe int_to.s convert.o structure.o mylist.o rgx.o
./int_to.exe input.txt


