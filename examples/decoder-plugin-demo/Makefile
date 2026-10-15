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
# The per-user plugin dir is `wavecrux/decoders` inside WaveCrux's
# application-support folder, which is named after the app's identifier:
# the WaveCrux download (WaveCrux Pro) and a build of this open-core
# repository use different ones. `make install` targets the download;
#   make install EDITION=open
# targets an open-core build, and
#   make install INSTALL_DIR=/some/dir
# installs anywhere. Settings → Decoders → Plugins → Open plugin directory
# shows the folder the running app actually scans.
#
# The header path is relative to this directory, so this Makefile
# assumes you ran it from inside `examples/decoder-plugin-demo/`.

CC      ?= cc
INCLUDE  = -I../../include
CFLAGS  ?= -O2 -Wall -Wextra -std=c11

# `pro` for the WaveCrux download, `open` for an open-core build.
EDITION ?= pro
ifeq ($(filter $(EDITION),pro open),)
    $(error EDITION must be pro or open, not '$(EDITION)')
endif

# path_provider's application-support folder plus `wavecrux/decoders`.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    EXT          = dylib
    SHARED_FLAGS = -dynamiclib -fPIC
    APP_ID_pro   = com.ferriteengineering.wavecruxPro
    APP_ID_open  = com.ferriteengineering.wavecrux
    INSTALL_DIR ?= $(HOME)/Library/Application Support/$(APP_ID_$(EDITION))/wavecrux/decoders
else ifeq ($(UNAME_S),Linux)
    EXT          = so
    SHARED_FLAGS = -shared -fPIC
    APP_ID_pro   = com.ferriteengineering.wavecrux_pro
    APP_ID_open  = com.ferriteengineering.wavecrux
    XDG_DATA_HOME ?= $(HOME)/.local/share
    INSTALL_DIR ?= $(XDG_DATA_HOME)/$(APP_ID_$(EDITION))/wavecrux/decoders
else
    $(error Unsupported uname=$(UNAME_S). Use the CMakeLists.txt for Windows builds.)
endif

LIB_NAME = libwavecrux_onewire.$(EXT)

.PHONY: all clean install

all: $(LIB_NAME)

$(LIB_NAME): onewire_decoder.c ../../include/wavecrux_decoder.h
	$(CC) $(CFLAGS) $(INCLUDE) $(SHARED_FLAGS) -o $@ onewire_decoder.c

install: $(LIB_NAME)
	mkdir -p "$(INSTALL_DIR)"
	cp $(LIB_NAME) "$(INSTALL_DIR)/"
	@echo "Installed $(LIB_NAME) to $(INSTALL_DIR)/"

clean:
	rm -f $(LIB_NAME)
