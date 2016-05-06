# Constants
CC = gcc.exe
CPP = g++.exe
WINDRES = windres.exe
RES = LangCheck.res
RC = LangCheck.rc
OBJDIR = obj
OBJ = $(OBJDIR)/main.o $(OBJDIR)/LangFile.o $(OBJDIR)/resource.o $(OBJDIR)/LangCompare.o
LIBS = -static-libgcc -m32 -mwindows -s
BIN = LangCheck.exe
CFLAGS = -m32 -Wall -Wextra -pedantic -mwindows -Wno-unused-parameter
CXXFLAGS = -m32 -Wall -Wextra -pedantic -mwindows -Wno-unused-parameter
RM = rm.exe -rf
MKDIR = mkdir

# Fix file name overlap problems
.PHONY:
	all cleanobj all-before cleanall

# Full rebuild rule
all: cleanall all-before $(BIN) cleanobj

# Partial rules
cleanobj:
	${RM} $(OBJDIR) $(RES)

cleanall:
	${RM} $(OBJDIR) $(RES) $(BIN)

all-before:
	${MKDIR} $(OBJDIR)

$(BIN): $(OBJ) $(RES)
	$(CPP) $(OBJ) $(RES) -o $(BIN) $(LIBS)

$(OBJDIR)/main.o: main.cpp
	$(CPP) -c main.cpp -o obj/main.o $(CXXFLAGS)

$(OBJDIR)/LangFile.o: LangFile.cpp
	$(CPP) -c LangFile.cpp -o obj/LangFile.o $(CXXFLAGS)

$(OBJDIR)/resource.o: resource.cpp
	$(CPP) -c resource.cpp -o obj/resource.o $(CXXFLAGS)

$(OBJDIR)/LangCompare.o: LangCompare.cpp
	$(CPP) -c LangCompare.cpp -o obj/LangCompare.o $(CXXFLAGS)

$(RES): $(RC)
	$(WINDRES) -i $(RC) -F pe-i386 --input-format=rc -o $(RES) -O coff