# Constants
CC = gcc.exe
CPP = g++.exe
WINDRES = windres.exe
RES = devcppPortable.res
RC = devcppPortable.rc
SRC = main.cpp
OBJ = main.o
LIBS = -static-libgcc lib/libshlwapi.a -m32 -mwindows -s
BIN = ..\..\..\devcppPortable.exe
CFLAGS = -m32 -Wall -Wextra -pedantic -mwindows
CXXFLAGS = -m32 -Wall -Wextra -pedantic -mwindows
RM = rm.exe -f

# Fix file name overlap problems
.PHONY:
	all cleanobj cleanall

# Full rebuild rule
all: cleanall $(BIN) cleanobj

# Partial rules
cleanobj:
	${RM} $(OBJ) $(RES)

cleanall:
	${RM} $(OBJ) $(RES) $(BIN)

$(BIN): $(OBJ) $(RES)
	$(CPP) $(OBJ) $(RES) -o $(BIN) $(LIBS)

$(OBJ): $(SRC)
	$(CPP) -c $(SRC) -o $(OBJ) $(CXXFLAGS)

$(RES): $(RC)
	$(WINDRES) -i $(RC) -F pe-i386 --input-format=rc -o $(RES) -O coff