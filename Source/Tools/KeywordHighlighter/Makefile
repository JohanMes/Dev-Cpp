# Constants
CC = gcc.exe
CPP = g++.exe
SRC = main.cpp
OBJ = main.o
LIBS = -static-libgcc -m32 -s
BIN = KeywordHighlighter.exe
CFLAGS = -m32 -Wall -Wextra -pedantic -std=c++11
CXXFLAGS = -m32 -Wall -Wextra -pedantic -std=c++11
RM = rm.exe -f

# Fix file name overlap problems
.PHONY:
	all cleanobj cleanall

# Full rebuild rule
all: cleanall $(BIN) cleanobj

# Partial rules
cleanobj:
	${RM} $(OBJ) 

cleanall:
	${RM} $(OBJ) $(BIN)

$(BIN): $(OBJ)
	$(CPP) $(OBJ) -o $(BIN) $(LIBS)

$(OBJ): $(SRC)
	$(CPP) -c $(SRC) -o $(OBJ) $(CXXFLAGS)