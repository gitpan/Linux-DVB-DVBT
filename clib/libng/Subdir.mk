libng ?= .

CFLAGCFLAGS += -I$(libng)


OBJS-libng := \
 $(libng)/parse-mpeg.o \
 $(libng)/parse-dvb.o

