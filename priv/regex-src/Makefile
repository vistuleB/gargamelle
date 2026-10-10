CC ?= cc
CFLAGS ?= -O2
SOURCES = gargamelle_regex_port.c libregexp.c libunicode.c cutils.c
HEADERS = libregexp.h libregexp-opcode.h libunicode.h libunicode-table.h unicode_gen_def.h cutils.h
TARGET = ../../build/native/gargamelle_regex_port

all: $(TARGET)

$(TARGET): $(SOURCES) $(HEADERS)
	mkdir -p ../../build/native
	$(CC) $(CFLAGS) -std=c11 -I. $(SOURCES) -o $(TARGET)

.PHONY: all
