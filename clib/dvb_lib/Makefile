CFLAGS   := -g
#CFLAGS   += -pedantic
#CFLAGS   += -std=gnu99
#CFLAGS   += -O3
CFLAGS   += -O0
CFLAGS   += -fPIC
CFLAGS   += -I.
CFLAGS   += -D_LARGEFILE_SOURCE
CFLAGS   += -D_FILE_OFFSET_BITS=64
CFLAGS   += -D_GNU_SOURCE
CFLAGS   += -DHAVE_DVB

ifdef TESTDEF
	CFLAGS += -D $(TESTDEF)
endif

OBJS-libdvb_lib := \
 struct-dvb.o \
 dvb_tune.o \
 dvb_stream.o \
 dvb_epg.o \
 dvb_debug.o  \
 dvb_scan.o \
 dvb_lib.o \
 dvb_error.o

# libng
libng := ../libng
include $(libng)/Subdir.mk


libdvb_lib.a: $(OBJS-libdvb_lib) $(OBJS-libng)
	$(AR) cr libdvb_lib.a $(OBJS-libdvb_lib) $(OBJS-libng)
	ranlib libdvb_lib.a

clean::
	rm -f libdvb_lib.a
	rm -f *.o
	rm -f $(libng)/*.a
	rm -f $(libng)/*.o

