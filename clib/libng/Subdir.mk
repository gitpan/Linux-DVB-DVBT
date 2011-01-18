ifndef libng
libng := .
endif

CFLAGS += -I$(libng)


OBJS-libng := \
 $(libng)/parse-mpeg.o \
 $(libng)/parse-dvb.o

