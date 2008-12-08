#ifndef DVB_EPG
#define DVB_EPG

#include <inttypes.h>
#include <list.h>

#include "dvb.h"


#define EPG_FLAG_AUDIO_MONO      (1<<0)
#define EPG_FLAG_AUDIO_STEREO    (1<<1)
#define EPG_FLAG_AUDIO_DUAL      (1<<2)
#define EPG_FLAG_AUDIO_MULTI     (1<<3)
#define EPG_FLAG_AUDIO_SURROUND  (1<<4)
#define EPG_FLAGS_AUDIO          (0xff)

#define EPG_FLAG_VIDEO_4_3       (1<< 8)
#define EPG_FLAG_VIDEO_16_9      (1<< 9)
#define EPG_FLAG_VIDEO_HDTV      (1<<10)
#define EPG_FLAGS_VIDEO          (0xff << 8)

#define EPG_FLAG_SUBTITLES       (1<<16)

struct epgitem {
    struct list_head    next;
    int                 id;
    int                 tsid;
    int                 pnr;
    int                 updated;
    time_t              start;       /* unix epoch */
    time_t              stop;
    char                lang[4];
    char                name[128];
    char                stext[256];
    char                *etext;
    char                *cat[4];
    uint64_t            flags;

    /* for the epg store */
    int                 row;
    int                 playing;
    struct station      *station;
};

extern struct list_head epg_list;
extern time_t eit_last_new_record;
extern int    eit_count_records;

struct eit_state;

struct list_head * get_eit(struct dvb_state *dvb,  int section, int mask, int verbose, int alive);

//extern struct epgitem* eit_lookup(int tsid, int pnr, time_t when, int debug);

#endif
