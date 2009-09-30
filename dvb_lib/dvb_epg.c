#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>
#include <errno.h>
#include <inttypes.h>
#include <sys/poll.h>

#include "dvb_tune.h"
#include "dvb_epg.h"
#include "grab-ng.h"

/* ----------------------------------------------------------------------- */

static char *content_desc[256] = {
    [ 0x10 ] = "Film|movie/drama (general)",
    [ 0x11 ] = "Film|detective/thriller",
    [ 0x12 ] = "Film|adventure/western/war",
    [ 0x13 ] = "Film|science fiction/fantasy/horror",
    [ 0x14 ] = "Film|comedy",
    [ 0x15 ] = "Film|soap/melodrama/folkloric",
    [ 0x16 ] = "Film|romance",
    [ 0x17 ] = "Film|serious/classical/religious/historical movie/drama",
    [ 0x18 ] = "Film|adult movie/drama",

    [ 0x20 ] = "News|news/current affairs (general)",
    [ 0x21 ] = "News|news/weather report",
    [ 0x22 ] = "News|news magazine",
    [ 0x23 ] = "News|documentary",
    [ 0x24 ] = "News|discussion/interview/debate",

    [ 0x30 ] = "Show|show/game show (general)",
    [ 0x31 ] = "Show|game show/quiz/contest",
    [ 0x32 ] = "Show|variety show",
    [ 0x33 ] = "Show|talk show",

    [ 0x40 ] = "Sports|sports (general)",
    [ 0x41 ] = "Sports|special events (Olympic Games, World Cup etc.)",
    [ 0x42 ] = "Sports|sports magazines",
    [ 0x43 ] = "Sports|football/soccer",
    [ 0x44 ] = "Sports|tennis/squash",
    [ 0x45 ] = "Sports|team sports (excluding football)",
    [ 0x46 ] = "Sports|athletics",
    [ 0x47 ] = "Sports|motor sport",
    [ 0x48 ] = "Sports|water sport",
    [ 0x49 ] = "Sports|winter sports",
    [ 0x4A ] = "Sports|equestrian",
    [ 0x4B ] = "Sports|martial sports",

    [ 0x50 ] = "Children|children's/youth programmes (general)",
    [ 0x51 ] = "Children|pre-school children's programmes",
    [ 0x52 ] = "Children|entertainment programmes for 6 to 14",
    [ 0x53 ] = "Children|entertainment programmes for 10 to 16",
    [ 0x54 ] = "Children|informational/educational/school programmes",
    [ 0x55 ] = "Children|cartoons/puppets",

    [ 0x60 ] = "Music|music/ballet/dance (general)",
    [ 0x61 ] = "Music|rock/pop",
    [ 0x62 ] = "Music|serious music/classical music",
    [ 0x63 ] = "Music|folk/traditional music",
    [ 0x64 ] = "Music|jazz",
    [ 0x65 ] = "Music|musical/opera",
    [ 0x66 ] = "Music|ballet",

    [ 0x70 ] = "Arts|arts/culture (without music, general)",
    [ 0x71 ] = "Arts|performing arts",
    [ 0x72 ] = "Arts|fine arts",
    [ 0x73 ] = "Arts|religion",
    [ 0x74 ] = "Arts|popular culture/traditional arts",
    [ 0x75 ] = "Arts|literature",
    [ 0x76 ] = "Arts|film/cinema",
    [ 0x77 ] = "Arts|experimental film/video",
    [ 0x78 ] = "Arts|broadcasting/press",
    [ 0x79 ] = "Arts|new media",
    [ 0x7A ] = "Arts|arts/culture magazines",
    [ 0x7B ] = "Arts|fashion",

    [ 0x80 ] = "Social|social/political issues/economics (general)",
    [ 0x81 ] = "Social|magazines/reports/documentary",
    [ 0x82 ] = "Social|economics/social advisory",
    [ 0x83 ] = "Social|remarkable people",

    [ 0x90 ] = "Education|education/science/factual topics (general)",
    [ 0x91 ] = "Education|nature/animals/environment",
    [ 0x92 ] = "Education|technology/natural sciences",
    [ 0x93 ] = "Education|medicine/physiology/psychology",
    [ 0x94 ] = "Education|foreign countries/expeditions",
    [ 0x95 ] = "Education|social/spiritual sciences",
    [ 0x96 ] = "Education|further education",
    [ 0x97 ] = "Education|languages",

    [ 0xA0 ] = "Leisure|leisure hobbies (general)",
    [ 0xA1 ] = "Leisure|tourism/travel",
    [ 0xA2 ] = "Leisure|handicraft",
    [ 0xA3 ] = "Leisure|motoring",
    [ 0xA4 ] = "Leisure|fitness & health",
    [ 0xA5 ] = "Leisure|cooking",
    [ 0xA6 ] = "Leisure|advertizement/shopping",
    [ 0xA7 ] = "Leisure|gardening",

    [ 0xB0 ] = "Special|original language",
    [ 0xB1 ] = "Special|black & white",
    [ 0xB2 ] = "Special|unpublished",
    [ 0xB3 ] = "Special|live broadcast",
};

/* ----------------------------------------------------------------------- */

struct eit_state {
    struct dvb_state    *dvb;
    int                 sec;
    int                 mask;
    int                 fd;
//    GIOChannel          *ch;
//    guint               id;
    int                 verbose;
    int                 alive;
};

/* ----------------------------------------------------------------------- */
struct versions {
    struct list_head    next;
    int                 tab;
    int                 pnr;
    int                 tsid;
    int                 part;
    int                 version;
};
static LIST_HEAD(seen_list);

/* ----------------------------------------------------------------------- */
/* ----------------------------------------------------------------------- */
static int eit_seen(int tab, int pnr, int tsid, int part, int version)
{
    struct versions   *ver;
    struct list_head  *item;
    int seen = 0;

    list_for_each(item,&seen_list) {
	ver = list_entry(item, struct versions, next);
	if (ver->tab  != tab)
	    continue;
	if (ver->pnr  != pnr)
	    continue;
	if (ver->tsid != tsid)
	    continue;
	if (ver->part != part)
	    continue;
	if (ver->version == version)
	    seen = 1;
	ver->version = version;
	return seen;
    }
    ver = malloc(sizeof(*ver));
    memset(ver,0,sizeof(*ver));
    ver->tab     = tab;
    ver->pnr     = pnr;
    ver->tsid    = tsid;
    ver->part    = part;
    ver->version = version;
    list_add_tail(&ver->next,&seen_list);
    return seen;
}

/* ----------------------------------------------------------------------- */

static struct epgitem* epgitem_get(int tsid, int pnr, int id)
{
    struct epgitem   *epg;
    struct list_head *item;

    list_for_each(item,&epg_list) {
	epg = list_entry(item, struct epgitem, next);
	if (epg->tsid != tsid)
	    continue;
	if (epg->pnr != pnr)
	    continue;
	if (epg->id != id)
	    continue;
	return epg;
    }
    epg = malloc(sizeof(*epg));
    memset(epg,0,sizeof(*epg));
    epg->tsid    = tsid;
    epg->pnr     = pnr;
    epg->id      = id;
    epg->row     = -1;
    epg->updated++;
    list_add_tail(&epg->next,&epg_list);
    eit_count_records++;
    return epg;
}

/* ----------------------------------------------------------------------- */
static time_t decode_mjd_time(int mjd, int start)
{
    struct tm tm;
    time_t t;
    int y2,m2,k;

    memset(&tm,0,sizeof(tm));

    /* taken as-is from EN-300-486 */
    y2 = (int)((mjd - 15078.2) / 365.25);
    m2 = (int)((mjd - 14956.1 - (int)(y2 * 365.25)) / 30.6001);
    k  = (m2 == 14 || m2 == 15) ? 1 : 0;
    tm.tm_mday = mjd - 14956 - (int)(y2 * 365.25) - (int)(m2 * 30.6001);
    tm.tm_year = y2 + k + 1900;
    tm.tm_mon  = m2 - 1 - k * 12;

    /* time is bcd ... */
    tm.tm_hour  = ((start >> 20) & 0xf) * 10;
    tm.tm_hour += ((start >> 16) & 0xf);
    tm.tm_min   = ((start >> 12) & 0xf) * 10;
    tm.tm_min  += ((start >>  8) & 0xf);
    tm.tm_sec   = ((start >>  4) & 0xf) * 10;
    tm.tm_sec  += ((start)       & 0xf);

#if 0
    fprintf(stderr,"mjd %d, time 0x%06x  =>  %04d-%02d-%02d %02d:%02d:%02d",
	    mjd, start,
	    tm.tm_year, tm.tm_mon, tm.tm_mday,
	    tm.tm_hour, tm.tm_min, tm.tm_sec);
#endif

    /* convert to unix epoch */
    tm.tm_mon--;
    tm.tm_year -= 1900;
    t = mktime(&tm);
    t -= timezone;

#if 0
    {
	char buf[16];

	strftime(buf,sizeof(buf),"%H:%M:%S",&tm);
	fprintf(stderr,"  =>  %s",buf);

	gmtime_r(&t,&tm);
	strftime(buf,sizeof(buf),"%H:%M:%S GMT",&tm);
	fprintf(stderr,"  =>  %s",buf);

	localtime_r(&t,&tm);
	strftime(buf,sizeof(buf),"%H:%M:%S %z",&tm);
	fprintf(stderr,"  =>  %s\n",buf);
    }
#endif

    return t;
}

/* ----------------------------------------------------------------------- */
static int decode_length(int length)
{
    int hour, min, sec;

    /* time is bcd ... */
    hour  = ((length >> 20) & 0xf) * 10;
    hour += ((length >> 16) & 0xf);
    min   = ((length >> 12) & 0xf) * 10;
    min  += ((length >>  8) & 0xf);
    sec   = ((length >>  4) & 0xf) * 10;
    sec  += ((length)       & 0xf);

    return hour * 3600 + min * 60 + sec;
}

/* ----------------------------------------------------------------------- */
static void dump_data(unsigned char *data, int len)
{
    int i;

    for (i = 0; i < len; i++) {
	if (isprint(data[i]))
	    fprintf(stderr,"%c", data[i]);
	else
	    fprintf(stderr,"0x%02x ", (int)data[i]);
    }
}

/* ----------------------------------------------------------------------- */
static void parse_eit_desc(unsigned char *desc, int dlen,
			   struct epgitem *epg, int verbose)
{
    int i,j,tag,len,len2,len3;
    int dump,slen,part,pcount;

    for (i = 0; i < dlen; i += desc[i+1] +2) {
	tag = desc[i];
	len = desc[i+1];

	dump = 0;

if (verbose > 1)
{
fprintf(stderr," TAG 0x%02x: ", tag);
dump=1;
}


	switch (tag) {
	case 0x4a: /*  linkage descriptor */
		/** TO DO **/
	    if (verbose > 1)
	    {
	    fprintf(stderr," *linkage descriptor");
		dump = 1;
	    }
		break;

	case 0x4d: /*  short event (eid) */
	    len2 = desc[i+5];
	    len3 = desc[i+6+len2];

//if ( (len2<0) || (len3<0) )
//{
//	fprintf(stderr, "** TAG 0x%02x len2=0x%08x len3=0x%08x\n", tag, len2, len3) ;
//    fprintf(stderr," 0x%02x[",desc[i]);
//    dump_data(desc+i+2,len);
//    fprintf(stderr,"]");
//}

	    memcpy(epg->lang,desc+i+2,3);
	    if (len2>0) mpeg_parse_psi_string((char*)desc+i+6,    len2, epg->name,
				  sizeof(epg->name)-1);
	    if (len3>0) mpeg_parse_psi_string((char*)desc+i+7+len2, len3, epg->stext,
				  sizeof(epg->stext)-1);
	    if (0 == strcmp(epg->name, epg->stext))
		memset(epg->stext, 0, sizeof(epg->stext));
	    break;

	case 0x4e: /*  extended event (eid) */
	    slen    = (epg->etext ? strlen(epg->etext) : 0);
	    part   = (desc[i+2] >> 4) & 0x0f;
	    pcount = (desc[i+2] >> 0) & 0x0f;
	    if (verbose > 1)
		fprintf(stderr,"eit: ext event: %d/%d\n",part,pcount);
	    if (0 == part)
		slen = 0;
	    epg->etext = realloc(epg->etext, slen+512);
	    len2 = desc[i+6];     /* item list (not implemented) */
	    len3 = desc[i+7+len2];  /* description */
	    if (len3>0) mpeg_parse_psi_string((char*)desc+i+8+len2, len3, epg->etext+slen, 511);
	    if (len2) {
		if (verbose) {
		    fprintf(stderr," [not implemented: item list (ext descr)]");
		    dump = 1;
		}
	    }
	    break;

	case 0x4f: /*  time shift event */
	    if (verbose > 1)
	    {
		fprintf(stderr," *time shift event");
		dump = 1;
	    }
	    break;

	case 0x50: /*  component descriptor */
	    if (verbose > 1)
		fprintf(stderr," component=%d,%d",
			desc[i+2] & 0x0f, desc[i+3]);
	    if (1 == (desc[i+2] & 0x0f)) {
		/* video */
		switch (desc[i+3]) {
		case 0x01:
		case 0x05:
		    epg->flags |= EPG_FLAG_VIDEO_4_3;
		    break;
		case 0x02:
		case 0x03:
		case 0x06:
		case 0x07:
		    epg->flags |= EPG_FLAG_VIDEO_16_9;
		    break;
		case 0x09:
		case 0x0d:
		    epg->flags |= EPG_FLAG_VIDEO_4_3;
		    epg->flags |= EPG_FLAG_VIDEO_HDTV;
		    break;
		case 0x0a:
		case 0x0b:
		case 0x0e:
		case 0x0f:
		    epg->flags |= EPG_FLAG_VIDEO_16_9;
		    epg->flags |= EPG_FLAG_VIDEO_HDTV;
		    break;
		}
	    }
	    if (2 == (desc[i+2] & 0x0f)) {
		/* audio */
		switch (desc[i+3]) {
		case 0x01:
		    epg->flags |= EPG_FLAG_AUDIO_MONO;
		    break;
		case 0x02:
		    epg->flags |= EPG_FLAG_AUDIO_DUAL;
		    break;
		case 0x03:
		    epg->flags |= EPG_FLAG_AUDIO_STEREO;
		    break;
		case 0x04:
		    epg->flags |= EPG_FLAG_AUDIO_MULTI;
		    break;
		case 0x05:
		    epg->flags |= EPG_FLAG_AUDIO_SURROUND;
		    break;
		}
	    }
	    if (3 == (desc[i+2] & 0x0f)) {
		/* subtitles / vbi */
		epg->flags |= EPG_FLAG_SUBTITLES;
	    }
	    break;

	case 0x53: /*  CA descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *CA descriptor");
		dump = 1;
	    }
	    break ;

	case 0x54: /*  content descriptor */
	    if (verbose > 1) {
		for (j = 0; j < len; j+=2) {
		    int d = desc[i+j+2];
		    fprintf(stderr," content=0x%02x:",d);
		    if (content_desc[d])
			fprintf(stderr,"%s",content_desc[d]);
		    else
			fprintf(stderr,"?");
		}
	    }
	    for (j = 0; j < len; j+=2) {
		int d = desc[i+j+2];
		int c;
		if (!content_desc[d])
		    continue;
		for (c = 0; c < DIMOF(epg->cat); c++) {
		    if (NULL == epg->cat[c])
			break;
		    if (content_desc[d] == epg->cat[c])
			break;
		}
		if (c == DIMOF(epg->cat))
		    continue;
		epg->cat[c] = content_desc[d];
	    }
	    break;

	case 0x55: /*  parental rating */
	    if (verbose > 1)
	    {
		fprintf(stderr," *parental rating");
		dump = 1;
	    }
	    break;

	case 0x57: /*  telephone descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *telephone descriptor");
		dump = 1;
	    }
	    break;

	case 0x5E:
	case 0x5F:
	case 0x61:
	    if (verbose > 1)
		{
		fprintf(stderr," *TAG 0x%02x", tag);
		dump = 1;
	    }
	    break ;

	case 0x64: /*  data broadcast descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *data broadcast descriptor");
		dump = 1;
	    }
	    break;

	case 0x69: /*  PDC descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *PDC descriptor");
		dump = 1;
	    }
	    break;

	case 0x75: /*  TVA id descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *TVA id descriptor");
		dump = 1;
	    }
	    break;

	case 0x76: /* TVA content descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *TVA content descriptor");
		dump = 1;
	    }
	    break;

	case 0x7F: /* extension descriptor */
	    if (verbose > 1)
	    {
		fprintf(stderr," *extension descriptor");
		dump = 1;
	    }
	    break;

	default:
	    if (verbose > 1)
	    {
		fprintf(stderr," *UNEXPECTED TAG 0x%02x", tag);
		dump = 1;
	    }
	    break;
	}

	if (dump) {
	    fprintf(stderr," 0x%02x[",desc[i]);
	    dump_data(desc+i+2,len);
	    fprintf(stderr,"]");
	}

    if (verbose > 1)
    {
	fprintf(stderr,"\n");
    }

    }
}

/* ----------------------------------------------------------------------- */
static int last_seen = 0 ;
static int mpeg_parse_psi_eit(unsigned char *data, int verbose)
{
    int tab,pnr,version,current,len;
    int j,dlen,tsid,nid,part,parts,seen;
    struct epgitem *epg;
    int id,mjd,start,length;

    tab     = mpeg_getbits(data, 0,8);
    len     = mpeg_getbits(data,12,12) + 3 - 4;
    pnr     = mpeg_getbits(data,24,16);
    version = mpeg_getbits(data,42,5);
    current = mpeg_getbits(data,47,1);
    if (!current)
	return len+4;

    part  = mpeg_getbits(data,48, 8);
    parts = mpeg_getbits(data,56, 8);
    tsid  = mpeg_getbits(data,64,16);
    nid   = mpeg_getbits(data,80,16);
    seen  = eit_seen(tab,pnr,tsid,part,version);
last_seen = seen ;
    if (seen)
	return len+4;

    eit_last_new_record = time(NULL);
    if (verbose>1)
	fprintf(stderr,
		"ts [eit]: tab 0x%x pnr %3d ver %2d tsid %d nid %d [%d/%d]\n",
		tab, pnr, version, tsid, nid, part, parts);

    j = 112;
    while (j < len*8) {
	id     = mpeg_getbits(data,j,16);
	mjd    = mpeg_getbits(data,j+16,16);
	start  = mpeg_getbits(data,j+32,24);
	length = mpeg_getbits(data,j+56,24);
	epg = epgitem_get(tsid,pnr,id);
	epg->start  = decode_mjd_time(mjd,start);
	epg->stop   = epg->start + decode_length(length);
	epg->updated++;

	if (verbose > 2)
	    fprintf(stderr,"  id %d mjd %d time %06x du %06x r %d ca %d  #",
		    id, mjd, start, length,
		    mpeg_getbits(data,j+80,3),
		    mpeg_getbits(data,j+83,1));
	dlen = mpeg_getbits(data,j+84,12);
	j += 96;
	parse_eit_desc(data + j/8, dlen, epg, verbose);
	if (verbose > 3) {
	    fprintf(stderr,"\n");
	    fprintf(stderr,"    n: %s\n",epg->name);
	    fprintf(stderr,"    s: %s\n",epg->stext);
	    fprintf(stderr,"    e: %s\n",epg->etext);
	    fprintf(stderr,"\n");
	}
	j += 8*dlen;
    }

    if (verbose > 1)
	fprintf(stderr,"\n");
    return len+4;
}

/* ----------------------------------------------------------------------- */
/* public interface                                                        */

LIST_HEAD(epg_list);
time_t eit_last_new_record;
int    eit_count_records;




/* ----------------------------------------------------------------------- */
/* public interface                                                        */

#define CYCLES_NOUPDATES	100
#define CYCLES_WRITEFILE	500

/* ----------------------------------------------------------------------- */
struct list_head *get_eit(struct dvb_state *dvb,  int section, int mask, int verbose, int alive)
{
	int n;
	time_t t;
	unsigned char buf[4096];
	struct dmx_sct_filter_params sctFilterParams;
	struct pollfd ufd;
	int found = 0;

struct eit_state *eit;
unsigned int to = 10 ;

unsigned int updates=0;
unsigned int cycles=0;

    eit = malloc(sizeof(*eit));
    memset(eit,0,sizeof(*eit));

    eit->dvb  = dvb;
    eit->sec  = section;
    eit->mask = mask;
    eit->verbose = verbose;
    eit->alive = alive;
    eit->fd   = dvb_demux_req_section(eit->dvb,
					-1, 0x12,
					eit->sec, eit->mask,
					0, 20);


	t = 0;


	for(;;)
	{
		/* keep track of the number of times round the loop between file writes */
		++cycles ;

		if (verbose>5) fprintf(stderr, " + cycle=%u : updates=%u\n", cycles, updates) ;
		while (to > 0) {
			int res;

			memset(&ufd,0,sizeof(ufd));
			ufd.fd=eit->fd;
			ufd.events=POLLIN;

			if (verbose>5) fprintf(stderr, " + + poll\n") ;
			res = poll(&ufd,1,1000);
			if (0 == res) {
				fprintf(stderr, ".");
				fflush(stderr);
				to--;
				continue;
				}
			if (1 == res) {
				found = 1;
				break;
			}

			fprintf(stderr, "error polling for data\n");
			close(eit->fd);
			return (struct list_head *)0;
		}

		if (verbose>5) fprintf(stderr, " + get_section\n") ;

		if (dvb_demux_get_section(eit->fd, buf, sizeof(buf)) < 0)
		{
			eit->fd = dvb_demux_req_section(eit->dvb,
						eit->fd , 0x12,
						eit->sec, eit->mask,
						0, 20);
		}
		else
		{
			if (verbose>5) fprintf(stderr, " + parse PSI\n") ;
			mpeg_parse_psi_eit(buf, eit->verbose);

			/* increment number of new items if not previously seen */
			if (!last_seen)
			{
				++updates ;
			}

			/* do some handling if above a certain number of cycles */
			if (updates)
			{
				/* write file if got some new AND over cycle threshold */
				if (cycles > CYCLES_WRITEFILE)
				{
					if (verbose>5) fprintf(stderr, "File dump...\n") ;
//					eit_write_file(filename) ;
					updates=0;
					cycles = 0 ;

				}
			}
			/* nothing new so stop */
			else
			{
				if (cycles > CYCLES_NOUPDATES)
				{
if (verbose>5)
{
	fprintf(stderr,"epg complete\n") ;
}
cycles=0;
					return &epg_list ;
				}
			}
		}

	}


if (verbose>5)
{
	fprintf(stderr,"epg end\n") ;
}
cycles=0;
	return &epg_list ;
}

