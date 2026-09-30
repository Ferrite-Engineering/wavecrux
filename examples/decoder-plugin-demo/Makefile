# Makefile — builds the WaveCrux 1-Wire decoder demonstrator plugin.
#
# Builds onewire_decoder.c into a platform-appropriate shared library:
#   * Linux:   libwavecrux_onewire.so       (-shared -fPIC)
#   * macOS:   libwavecrux_onewire.dylib    (-dynamiclib)
#   * Windows: see ../README.md for the MinGW / MSVC instructions —
#              this Makefile is Unix-first.
#
# Build:
#   make           # produces the library next to this Makefile
#   make install   # copies the library to the per-user plugin dir
#   make clean     # removes the build artifact
#
# The header path is relative to this directory, so this Makefile
# assumes you ran it from inside `examples/decoder-plugin-demo/`.

CC      ?= cc
INCLUDE  = -I../../include
CFLAGS  ?= -O2 -Wall -Wextra -std=c11

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    EXT          = dylib
    SHARED_FLAGS = -dynamiclib -fPIC
    INSTALL_DIR  = $(HOME)/Library/Application\ Support/wavecrux/decoders
else ifeq ($(UNAME_S),Linux)
    EXT          = so
    SHARED_FLAGS = -shared -fPIC
    INSTALL_DIR  = $(HOME)/.config/wavecrux/decoders
else
    $(error Unsupported uname=$(UNAME_S). Use the CMakeLists.txt for Windows builds.)
endif

LIB_NAME = libwavecrux_onewire.$(EXT)

.PHONY: all clean install

all: $(LIB_NAME)

$(LIB_NAME): onewire_decoder.c ../../include/wavecrux_decoder.h
	$(CC) $(CFLAGS) $(INCLUDE) $(SHARED_FLAGS) -o $@ onewire_decoder.c

install: $(LIB_NAME)
	mkdir -p $(INSTALL_DIR)
	cp $(LIB_NAME) $(INSTALL_DIR)/
	@echo "Installed $(LIB_NAME) to $(INSTALL_DIR)/"

clean:
	rm -f $(LIB_NAME)
