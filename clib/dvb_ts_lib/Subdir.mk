libdvb_ts_lib ?= .

CFLAGS += -I$(libdvb_ts_lib)  -I$(libdvb_ts_lib)/si

OBJS-libdvb_ts_lib := \
	$(libdvb_ts_lib)/ts_parse.o \
	$(libdvb_ts_lib)/ts_skip.o \
	$(libdvb_ts_lib)/ts_split.o \
	$(libdvb_ts_lib)/ts_cut.o \
	$(libdvb_ts_lib)/ts_bits.o \
	$(libdvb_ts_lib)/dvbsnoop/crc32.o \
	$(libdvb_ts_lib)/tables/parse_si_eit.o\
	$(libdvb_ts_lib)/tables/parse_si_sdt.o\
	$(libdvb_ts_lib)/si/parse_desc.o
