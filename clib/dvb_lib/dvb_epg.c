#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>
#include <errno.h>
#include <inttypes.h>
#include <sys/poll.h>
#include <sys/ioctl.h>

#include <fcntl.h>
#include <sys/types.h>

#include "dvb_lib.h"
#include "dvb_tune.h"
#include "dvb_epg.h"
#include "dvb_error.h"
#include "dvb_debug.h"

/* ------------------------------------------------------------------------ */

/*
4.4.2 Terrestrial delivery systems
For terrestrial delivery systems bandwidth within a single transmitted TS is a valuable resource and in order to
safeguard the bandwidth allocated to the primary services receivable from the actual multiplex, the following minimum
repetition rates are specified in order to reflect the need to impose a limit on the amount of available bandwidth used for
this purpose:
a) all sections of the NIT shall be transmitted at least every 10 s;
b) all sections of the BAT shall be transmitted at least every 10 s, if present;
c) all sections of the SDT for the actual multiplex shall be transmitted at least every 2 s;
d) all sections of the SDT for other TSs shall be transmitted at least every 10 s if present;
e) all sections of the EIT Present/Following Table for the actual multiplex shall be transmitted at least every 2 s;
f) all sections of the EIT Present/Following Tables for other TSs shall be transmitted at least every 20 s if
present.

The repetition rates for further EIT tables will depend greatly on the number of services and the quantity of related SI
information. The following transmission intervals should be followed if practicable but they may be increased as the use
of EIT tables is increased. The times are the consequence of a compromise between the acceptable provision of data to a
viewer and the use of multiplex bandwidth.

a) all sections of the EIT Schedule table for the first full day for the actual TS, shall be transmitted at least every
10 s, if present;
b) all sections of the EIT Schedule table for the first full day for other TSs, shall be transmitted at least every
60 s, if present;
c) all sections of the EIT Schedule table for the actual TS, shall be transmitted at least every 30 s, if present;
d) all sections of the EIT Schedule table for other TSs, shall be transmitted at least every 300 s, if present;
e) the TDT and TOT shall be transmitted at least every 30 s.

*/

/* ----------------------------------------------------------------------------- */

//EIT actual present-following		0x12 2s / 25 ms [2]
//EIT other present-following		0x12 10s / 25 ms [2]

// Max section size is 4096
#define EIT_BUFF_SIZE			4096

// number of cycles of no new data until we time out and stop
#define CYCLES_NOUPDATES		100

// number of cycles with new data at which point we restart the counters
#define CYCLES_RESTART			500

// Poll timeout in ms
#define POLL_TIMEOUT			1000

// Number of times round the poll loop before giving up (~10s)
#define POLL_CYCLES				20

// Number of times we retry requesting the section
# define SECTION_RETRY_COUNT	3


/* ----------------------------------------------------------------------- */
//#define CHECK_PARTS
//#define BUFF_TEST

/* ----------------------------------------------------------------------- */

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

int epg_demux_get_section(int fd, unsigned char *buf, int len)
{
int rc;
#ifdef BUFF_TEST
unsigned char buf2[EIT_BUFF_SIZE];
int rc2;
#endif

    memset(buf,0,len);
    if ((rc = read(fd, buf, len)) < 0)
    {
		if ((ETIMEDOUT != errno && EOVERFLOW != errno) || dvb_debug)
		{
			fprintf(stderr,"dvb mux: read: %s [%d] rc=%d\n", strerror(errno), errno, rc);
		}
    }
#ifdef BUFF_TEST
    else
    {
        if ((rc2 = read(fd, buf2, sizeof(buf2))) > 0)
        {
   			fprintf(stderr,"#!#! Got second section buffer! rc=%d\n", rc2);
        }
    }
#endif
	return rc;
}



/* ----------------------------------------------------------------------- */
LIST_HEAD(parts_list);
int parts_remaining=0 ;

/* ----------------------------------------------------------------------- */
LIST_HEAD(errs_list);
int total_errors=0 ;

/* ----------------------------------------------------------------------- */
/* ----------------------------------------------------------------------- */
// Return if seen ; otherwise create a new one
static int eit_seen(int tab, int pnr, int tsid, int part, int version)
{
struct versions   *ver;
struct list_head  *item;
int seen = 0;
int dbg_count = 0 ;
char *dbg_time ;

if (dvb_debug >= 5) dbg_timer_start() ;

    list_for_each(item,&seen_list) {
    	++dbg_count ;
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

if (dvb_debug >= 5)
{
	dbg_timer_stop() ;
	dbg_time = dbg_sprintf_duration("%M:%S") ;
	fprintf_timestamp(stderr, "eit_seen() found : count %d took %s\n", dbg_count, dbg_time) ;
}

		return seen;
    }

if (dvb_debug >= 5)
{
	dbg_timer_stop() ;
	dbg_time = dbg_sprintf_duration("%M:%S") ;
	fprintf_timestamp(stderr, "eit_seen() not found : count %d took %s\n", dbg_count, dbg_time) ;
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
// get existing or return created
static struct epgitem* epgitem_get(int tsid, int pnr, int id, int *new)
{
struct epgitem   *epg;
struct list_head *item;
int dbg_count = 0 ;
char *dbg_time ;

if (dvb_debug >= 5) dbg_timer_start() ;

    *new=0;
    list_for_each(item,&epg_list) {
    	++dbg_count ;
		epg = list_entry(item, struct epgitem, next);
		if (epg->tsid != tsid)
			continue;
		if (epg->pnr != pnr)
			continue;
		if (epg->id != id)
			continue;

	    if (dvb_debug>1)
			fprintf(stderr,
				"epgitem_get(tsid %d pnr %3d id %d) - already created\n",
				tsid, pnr, id);

	    if (dvb_debug >= 5)
	    {
	    	dbg_timer_stop() ;
	    	dbg_time = dbg_sprintf_duration("%M:%S") ;
	    	fprintf_timestamp(stderr, "epgitem_get() found : count %d took %s\n", dbg_count, dbg_time) ;
	    }

		return epg;
    }

if (dvb_debug >= 5)
{
	dbg_timer_stop() ;
	dbg_time = dbg_sprintf_duration("%M:%S") ;
	fprintf_timestamp(stderr, "epgitem_get() not found : count %d took %s\n", dbg_count, dbg_time) ;
}

	*new=1;
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
// get existing or return created
static struct partitem* get_parts(int tsid, int pnr, int parts)
{
struct partitem   *partp;
struct list_head *item;

    list_for_each(item,&parts_list) {
		partp = list_entry(item, struct partitem, next);
		if (partp->tsid != tsid)
			continue;
		if (partp->pnr != pnr)
			continue;

		return partp;
    }

    partp = malloc(sizeof(*partp));
    memset(partp,0,sizeof(*partp));
    partp->tsid    = tsid;
    partp->pnr     = pnr;
    partp->parts   = parts;
    partp->parts_left   = parts;

    list_add_tail(&partp->next,&parts_list);
    parts_remaining += parts ;
    return partp;
}


/* ----------------------------------------------------------------------- */
// get existing or return created - inc counts
static struct erritem* get_errs(int freq, int section)
{
struct erritem   *errp;
struct list_head *item;

    list_for_each(item,&errs_list) {
		errp = list_entry(item, struct erritem, next);
		if (errp->freq != freq)
			continue;
		if (errp->section != section)
			continue;

		++errp->errors ;
	    ++total_errors ;

	    return errp;
    }

    errp = malloc(sizeof(*errp));
    memset(errp,0,sizeof(*errp));
    errp->freq    = freq;
    errp->section = section;
    errp->errors = 1 ;

    list_add_tail(&errp->next,&errs_list);
    ++total_errors ;
    return errp;
}

/* ----------------------------------------------------------------------- */
// Clear the counts for specific freq/section
static struct erritem* clear_errs(int freq, int section)
{
struct erritem   *errp;

	// get it
	errp = get_errs(freq, section) ;

	// remove from total
	total_errors -= errp->errors ;

	// clear error count
	errp->errors = 0 ;

    return errp;
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
    int i,j,k,tag,len,len2,len3;
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

				//	content_identifier_descriptor() {
				//		descriptor_tag 8 uimsbf
				//		descriptor_length 8 uimsbf
				//		for (i=0;i<N;i++) {
				//			crid_type 6 uimsbf
				//			crid_location 2 uimsbf
				//			if (crid_location == '00' ) {
				//				crid_length 8 uimsbf
				//				for (j=0;j<crid_length;j++) {
				//					crid_byte 8 uimsbf
				//				}
				//			}
				//			if (crid_location == '01' ) {
				//				crid_ref 16 uimsbf
				//			}
				//		}
				//	}
				j=0;
				while (j < len*8) {
					char crid_byte[256] = "";
					int crid_type = mpeg_getbits(desc+i+2,  j, 6);
					int crid_loc = mpeg_getbits(desc+i+2,  j+6, 2) ;
					j += 8 ;
					if (crid_loc == 0)
					{
						int crid_len = mpeg_getbits(desc+i+2,  j, 8) ;
						j+=8;
						for (k=0; (k < crid_len) && (j<len*8); j+=8, k++)
						{
							if (k < 254)
							{
								crid_byte[k] = mpeg_getbits(desc+i+2, j, 8) ;
								crid_byte[k+1] = 0 ;
							}
						}
					}
					if (crid_loc == 1)
					{
						int crid_ref = mpeg_getbits(desc+i+2,  j, 16) ;
						j+=16 ;
					}

					if (crid_type == 0x01 || crid_type == 0x31)
					{
						strncpy(epg->tva_prog, crid_byte, 255);
					}
					else if (crid_type == 0x02 || crid_type == 0x32)
					{
						strncpy(epg->tva_series, crid_byte, 255);
					}
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
		} // switch

		if (dump) {
			fprintf(stderr," 0x%02x[",desc[i]);
			dump_data(desc+i+2,len);
			fprintf(stderr,"]");
		}

		if (verbose > 1)
		{
			fprintf(stderr,"\n");
		}

    } // for
}

/* ----------------------------------------------------------------------- */
static int last_seen = 0 ;
static int mpeg_parse_psi_eit(unsigned char *data, int verbose)
{
int tab,pnr,version,current,len, new, eit_count;
int j,dlen,tsid,nid,part,parts,seen, seg_last_section, last_table_id ;
struct epgitem *epg;
int id,mjd,start,length;

#ifdef CHECK_PARTS
struct partitem *partp ;
#endif

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
    seg_last_section   	= mpeg_getbits(data,96,8);
    last_table_id   	= mpeg_getbits(data,104,8);

    seen  = eit_seen(tab,pnr,tsid,part,version);
    last_seen = seen ;
    if (seen)
    {
        if (dvb_debug) fprintf(stderr, "eit_seen(tab=%d, pnr=%d, tsid=%d, part=%d, ver=%d)\n", tab,pnr,tsid,part,version) ;
    	return len+4;
    }

#ifdef CHECK_PARTS
    partp = get_parts(tsid, pnr, parts) ;
#endif

    // time of eit
    eit_last_new_record = time(NULL);

    if (verbose>1)
		fprintf(stderr,
			"ts [eit]: tab 0x%x pnr %3d ver %2d tsid %d nid %d [%d/%d] last_sect %d last_tab 0x%x\n",
			tab, pnr, version, tsid, nid, part, parts,
			seg_last_section, last_table_id);


    eit_count=0;
    j = 112;
    while (j < len*8) {
    	++eit_count;
		id     = mpeg_getbits(data,j,16);
		mjd    = mpeg_getbits(data,j+16,16);
		start  = mpeg_getbits(data,j+32,24);
		length = mpeg_getbits(data,j+56,24);

		epg = epgitem_get(tsid,pnr,id, &new);
		epg->start  = decode_mjd_time(mjd,start);
		epg->stop   = epg->start + decode_length(length);
		epg->updated++;

	    if (dvb_debug>1)
			fprintf(stderr,
				"eit item: tsid %d pnr %3d id %d [update count %d]\n",
				tsid, pnr, id,
				epg->updated);


#ifdef CHECK_PARTS
if (new) partp->parts_left-- ;
#endif

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

    if (dvb_debug)
    {
    	fprintf(stderr, "mpeg_parse_psi_eit() processed %d \n", eit_count);
    }

    return len+4;
}

/* ----------------------------------------------------------------------- */
/* public interface                                                        */

LIST_HEAD(epg_list);
time_t eit_last_new_record;
int    eit_count_records;




/* ----------------------------------------------------------------------- */
/* public interface                                                        */


/* ----------------------------------------------------------------------- */
void clear_epg()
{
struct list_head *item, *safe;
struct epgitem   *epg;
struct versions  *ver;
struct partitem  *partp;
struct erritem   *errp;

	/* Free up results */
	list_for_each_safe(item,safe,&epg_list)
	{
		epg = list_entry(item, struct epgitem, next);
		list_del(&epg->next);

		if (epg->etext) free(epg->etext) ;
		free(epg);
	};

   	list_for_each_safe(item,safe,&seen_list)
   	{
		ver = list_entry(item, struct versions, next);
		list_del(&ver->next);

		free(ver);
   	};
   	
   	list_for_each_safe(item,safe,&parts_list)
   	{
		partp = list_entry(item, struct partitem, next);
		list_del(&partp->next);

		free(partp);
   	};

   	list_for_each_safe(item,safe,&errs_list)
   	{
		errp = list_entry(item, struct erritem, next);
		list_del(&errp->next);

		free(errp);
   	};

   	parts_remaining = 0 ;
   	total_errors = 0 ;

}

/* ----------------------------------------------------------------------- */
struct list_head *get_eit(struct dvb_state *dvb,  int section, int mask, int verbose, int alive)
{
int n;
//	time_t t;
unsigned char buf[EIT_BUFF_SIZE];
struct dmx_sct_filter_params sctFilterParams;
struct pollfd ufd;
int found = 0;

unsigned int to = POLL_CYCLES ;

unsigned int updates=0;
unsigned int cycles=0;
int section_retries=SECTION_RETRY_COUNT;

struct eit_state *eit;
struct freqitem *current_freqi ;
int rc ;

	// start with no errors
	dvb_error_clear() ;

	// Set section filter
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
					/* oneshot */ 0,
					/* timeout */ 20);

#ifdef BUFF_TEST
    setNonblocking(eit->fd) ;
#endif

	// get current frequency info
	current_freqi = freqitem_get(&dvb->p) ;

	if (verbose)
	{
		fprintf(stderr, "Scanning section 0x%02x [mask 0x%02x]\n", section, mask) ;
	}
	if (dvb_debug) fprintf_timestamp(stderr, "== get_eit(section 0x%02x [mask 0x%02x]) start freq=%d Hz ==\n", section, mask, current_freqi->frequency) ;

//	// display tuning settings
//	if (dvb_debug >= 2) dvb_frontend_tune_info(dvb);

	// clear errors for this freq/section
	clear_errs(current_freqi->frequency, section) ;

	for(;;)
	{
		/* keep track of the number of times round the loop between counter restarts */
		++cycles ;

		if (dvb_debug>5) fprintf_timestamp(stderr, " + cycle=%u : updates=%u (last to=%d)\n", cycles, updates, to) ;

		to = POLL_CYCLES ;
		found = 0 ;
		while (to > 0) {
			int res;

			memset(&ufd,0,sizeof(ufd));
			ufd.fd=eit->fd;
			ufd.events=POLLIN;

			if (dvb_debug>5) fprintf(stderr, " + + poll\n") ;
			res = poll(&ufd,1,POLL_TIMEOUT);
			if (0 == res) {
				// got nothing
				if (verbose||alive)
				{
					fprintf(stderr, ".");
					fflush(stderr);
				}

				// try again
				to--;
				continue;
			}
			if (1 == res) {
				// got something to read
				found = 1;
				break;
			}

			//fprintf_timestamp(stderr, "error polling for data\n");
			SET_DVB_ERROR(ERR_EPG_POLL) ;
			close(eit->fd);
			return (struct list_head *)0;
		}

		if (dvb_debug>5) fprintf(stderr, " + get_section() fd=%d found=%d to=%d\n", eit->fd, found, to) ;

//		if (!found || (rc=dvb_demux_get_section(eit->fd, buf, sizeof(buf)) < 0) )
		rc = -99 ;
		if (found)
		{
			rc=epg_demux_get_section(eit->fd, buf, sizeof(buf)) ;
		}

		if (rc < 0)
		{
			// Got no data
			if (dvb_debug>5) fprintf_timestamp(stderr, " + + !! failed to get_section() - request retune (%d retries left) found=%d rc=%d\n", section_retries, found, rc) ;

			// actually sets the counters & creates an entry in the list iff required
			get_errs(current_freqi->frequency, section) ;

			if (--section_retries > 0)
			{
				eit->fd = dvb_demux_req_section(eit->dvb,
						eit->fd , 0x12,
						eit->sec, eit->mask,
						0, 20);
				if (dvb_debug>5) fprintf_timestamp(stderr, " + + retune fd=%d\n", eit->fd) ;
			}
			else
			{
				if (dvb_debug>5) fprintf_timestamp(stderr,"== epg complete - failed to get section ==\n") ;

				// assume we've finished - some tuners seem to indicate to poll() that they're ready even when they aren't
				return &epg_list ;	
			}
		}
		else
		{
			// Got data - reset counter
			section_retries = SECTION_RETRY_COUNT ;

			if (dvb_debug>5) fprintf_timestamp(stderr, " + parse PSI (%d bytes)\n", rc) ;

			// parse the data
			mpeg_parse_psi_eit(buf, eit->verbose);

			/* increment number of new items if not previously seen */
			if (!last_seen)
			{
				++updates ;
			}

			/* do some handling if above a certain number of cycles */
			if (updates)
			{
				/* restart counters if got some new AND over cycle threshold */
				if (cycles > CYCLES_RESTART)
				{
					if (dvb_debug>5) fprintf_timestamp(stderr, "counter restart...\n") ;
					updates=0;
					cycles = 0 ;
				}
			}
			/* nothing new so see if we can stop yet */
			else
			{
				// stop if we've timed out
				if (cycles > CYCLES_NOUPDATES)
				{
					if (dvb_debug>5) fprintf_timestamp(stderr,"== epg complete - no more updates ==\n") ;

					return &epg_list ;
				}
			}
		}

	}


	if (dvb_debug>5)
	{
		fprintf_timestamp(stderr, "== get_eit() END ==\n\n") ;
	}

	return &epg_list ;
}

