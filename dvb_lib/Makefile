CFLAGS   := -g
CFLAGS   += -O0
CFLAGS   += -I../libng

OBJS-libdvb_lib := \
	struct-dvb.o \
	dvb_tune.o \
	dvb_stream.o \
	dvb_epg.o \
	dvb_debug.o  \
	dvb_scan.o \
	dvb_lib.o
	
include ../libng/Subdir.mk

libdvb_lib.a: $(OBJS-libdvb_lib) $(OBJS-libng)
	$(AR) cr libdvb_lib.a $(OBJS-libdvb_lib) $(OBJS-libng)
	ranlib libdvb_lib.a

clean::
	rm -f libdvb_lib.a
	rm -f *.o
	rm -f ../libng/*.a
	rm -f ../libng/*.o

