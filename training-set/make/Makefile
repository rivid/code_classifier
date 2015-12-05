# The pre-processor and compiler options.
MY_CFLAGS = `pkg-config --cflags opencv boost` -I$(SRCROOT)

# The linker options.
MY_LIBS   = `pkg-config --libs opencv boost`

# The pre-processor options used by the cpp (man cpp for more).
CPPFLAGS  = -Wall
CFLAGS  = -g
CXXFLAGS= -g

# The root of the project.
SRCROOT   = .
SRCDIR    = 
RECURSION = 1

# The executable file name.
# If not specified, current directory name or `demo.out' will be used.
PROGRAM   = Main Main2 Subtitle/aa/bb/Main3

## Implicit Section: change the following only when necessary.
##==========================================================================

# The source file types (headers excluded).
# .c indicates C source files, and others C++ ones.
SRCEXTS = .c .C .cc .cpp .CPP .c++ .cxx .cp

# The header file types.
HDREXTS = .h .H .hh .hpp .HPP .h++ .hxx .hp

# The C++ program compiler.
CXX    = g++

# The C program compiler.
CC     = gcc

# The command used to delete file.
RM     = rm -f

CTAGS = ctags
CTAGSFLAGS =

# The directories in which source files reside.
SRCROOT := $(foreach d,$(SRCROOT),$(d:/=))
SRCDIRS := $(strip $(SRCROOT) $(SRCDIR))
SRCDIRS := $(foreach d,$(SRCDIRS),$(d:/=))
ifeq ($(RECURSION), 1)
SRCDIRS := $(shell find $(SRCDIRS) -type d | grep \\.git -v)
endif
SRCDIRS := $(sort $(SRCDIRS))
RMOBJS  := $(addsuffix /*.o, $(SRCDIRS))
RMDEPS  := $(RMOBJS:.o=.d)

# The options used in linking as well as in any direct use of ld.
LDFLAGS   =

## Stable Section: usually no need to be changed. But you can add more.
##==========================================================================
SHELL   = /bin/bash
EMPTY   =
SPACE   = $(EMPTY) $(EMPTY)
ifeq ($(PROGRAM),)
  CUR_PATH_NAMES = $(subst /,$(SPACE),$(subst $(SPACE),_,$(CURDIR)))
  PROGRAM = $(word $(words $(CUR_PATH_NAMES)),$(CUR_PATH_NAMES))
  ifeq ($(PROGRAM),)
    PROGRAM = demo.out
  endif
endif
ifeq ($(SRCDIRS),)
  SRCDIRS = .
endif
SOURCES = $(foreach d,$(SRCDIRS),$(wildcard $(addprefix $(d)/*,$(SRCEXTS))))
HEADERS = $(foreach d,$(SRCDIRS),$(wildcard $(addprefix $(d)/*,$(HDREXTS))))
SRC_CXX = $(filter-out %.c,$(SOURCES))
OBJS    = $(addsuffix .o, $(basename $(SOURCES)))
DEPS    = $(OBJS:.o=.d)

## Define some useful variables.
DEP_OPT = $(shell if `$(CC) --version | grep "gcc" >/dev/null`; then \
                  echo "-MM -MP"; else echo "-M"; fi )
DEPEND      = $(CC)  $(DEP_OPT)  $(MY_CFLAGS) $(CFLAGS) $(CPPFLAGS)
DEPEND.d    = $(subst -g ,,$(DEPEND))
COMPILE.c   = $(CC)  $(MY_CFLAGS) $(CFLAGS)   $(CPPFLAGS) -c
COMPILE.cxx = $(CXX) $(MY_CFLAGS) $(CXXFLAGS) $(CPPFLAGS) -c
LINK.c      = $(CC)  $(MY_CFLAGS) $(CFLAGS)   $(CPPFLAGS) $(LDFLAGS)
LINK.cxx    = $(CXX) $(MY_CFLAGS) $(CXXFLAGS) $(CPPFLAGS) $(LDFLAGS)

.PHONY: all objs tags ctags clean help show

# Delete the default suffixes
.SUFFIXES:

all: $(PROGRAM)

# Rules for creating dependency files (.d).
#------------------------------------------

%.d:%.c
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.C
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.cc
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.cpp
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.CPP
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.c++
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.cp
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

%.d:%.cxx
	@echo -n $(dir $<) > $@
	$(DEPEND.d) $< >> $@

# Rules for generating object files (.o).
#----------------------------------------
objs:$(OBJS)

%.o:%.c
	$(COMPILE.c) $< -o $@

%.o:%.C
	$(COMPILE.cxx) $< -o $@

%.o:%.cc
	$(COMPILE.cxx) $< -o $@

%.o:%.cpp
	$(COMPILE.cxx) $< -o $@

%.o:%.CPP
	$(COMPILE.cxx) $< -o $@

%.o:%.c++
	$(COMPILE.cxx) $< -o $@

%.o:%.cp
	$(COMPILE.cxx) $< -o $@

%.o:%.cxx
	$(COMPILE.cxx) $< -o $@

# Rules for generating the tags.
#-------------------------------------
tags: $(HEADERS) $(SOURCES)
	$(ETAGS) $(ETAGSFLAGS) $(HEADERS) $(SOURCES)

ctags: $(HEADERS) $(SOURCES)
	$(CTAGS) $(CTAGSFLAGS) $(HEADERS) $(SOURCES)

# Rules for generating the executable.
#-------------------------------------
COBJS = $(filter-out $(foreach d,$(PROGRAM), \
  $(addprefix $(SRCROOT)/,$(d).o)), $(OBJS))
$(PROGRAM):$(OBJS)
ifeq ($(SRC_CXX),)              # C program
	$(LINK.c)   $(COBJS) $(SRCROOT)/$@.o $(MY_LIBS) -o $@
	@echo Type $(SRCROOT)/$@ to execute the program.
else                            # C++ program
	$(LINK.cxx) $(COBJS) $(SRCROOT)/$@.o $(MY_LIBS) -o $@
	@echo Type $(SRCROOT)/$@ to execute the program.
endif

ifndef NODEP
ifneq ($(DEPS),)
  sinclude $(DEPS)
endif
endif

clean:
	$(RM) $(RMDEPS) $(RMOBJS)
	$(RM) $(PROGRAM) $(foreach d,$(PROGRAM),$(addprefix $(d),.exe))

# Show help.
help:
	@echo 'Generic Makefile for C/C++ Programs (gcmakefile) version 0.5'
	@echo 'Copyright (C) 2007, 2008 whyglinux <whyglinux@hotmail.com>'
	@echo
	@echo 'Usage: make [TARGET]'
	@echo 'TARGETS:'
	@echo '  all       (=make) compile and link.'
	@echo '  NODEP=yes make without generating dependencies.'
	@echo '  objs      compile only (no linking).'
	@echo '  ctags     create ctags for VI editor.'
	@echo '  clean 	   clean objects, the executable and dependencies.'
	@echo '  show      show variables (for debug use only).'
	@echo '  help      print this message.'
	@echo
	@echo 'Report bugs to <whyglinux AT gmail DOT com>.'

# Show variables (for debug use only.)
show:
	@echo 'PROGRAM     :' $(PROGRAM)
	@echo 'SRCDIRS     :' $(SRCDIRS)
	@echo 'HEADERS     :' $(HEADERS)
	@echo 'SOURCES     :' $(SOURCES)
	@echo 'SRC_CXX     :' $(SRC_CXX)
	@echo 'OBJS        :' $(OBJS)
	@echo 'DEPS        :' $(DEPS)
	@echo 'DEPEND      :' $(DEPEND)
	@echo 'COMPILE.c   :' $(COMPILE.c)
	@echo 'COMPILE.cxx :' $(COMPILE.cxx)
	@echo 'LINK.c      :' $(LINK.c)
	@echo 'LINK.cxx    :' $(LINK.cxx)
