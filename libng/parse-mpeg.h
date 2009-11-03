/*
 * MPEG1/2 transport and program stream parser and demuxer code.
 *
 * (c) 2003 Gerd Knorr <kraxel@bytesex.org>
 *
 */
#ifndef PARSE_MPEG
#define PARSE_MPEG

#include <inttypes.h>
#include "grab-ng.h"


#define TS_SIZE                   188

extern int mpeg_rate_n[16];
extern int mpeg_rate_d[16];
extern const char *mpeg_frame_s[];

extern char *psi_charset[0x20];
char *psi_service_type[0x100];


// List of tuned frequencies stored for each program
struct freq_info {
    struct list_head     next;

	int 				 frequency ;
} ;


/* data gathered from NIT during scan - info is added to the stream */
struct prog_info {
    struct list_head     next;

	/* from service_list_descriptor 0x41 */
	int 				 service_id ;
	int 				 service_type ;
	
	/* from descriptor 0x83 */
	int					 visible ;
	int					 lcn ;

} ;


/* ----------------------------------------------------------------------- */

#define PSI_NEW     42  // initial version, valid range is 0 ... 32
#define PSI_STR_MAX 64

struct psi_stream {
    struct list_head     next;
    int                  tsid;

    /* network */
    int                  netid;
    char                 net[PSI_STR_MAX];

    int                  frequency;

    char                 *bandwidth;
    char                 *code_rate_hp;
    char                 *code_rate_lp;
    char                 *constellation;
    char                 *transmission;
    char                 *guard;
    char                 *hierarchy;

    char                 *polarization;		// Not used
    int                  symbol_rate;		// Not used
    char                 *fec_inner;		// Not used

	// Other frequency list    
    int                  other_freq;
    int                  freq_list_len;
    int                  *freq_list;

    /* status info */
    int                  updated;
    int					 tuned;		// set when we've tuned to this transponder's freq

    /* program info i.e. LCN info */
    struct list_head     prog_info_list;
    
};


struct psi_program {
    struct list_head     next;
    int                  tsid;
    int                  pnr;
    int                  version;
    int                  running;
    int                  ca;
    
//    int					 tuned_freq; 	

	// keep a record of the currently tuend frequency when we saw this
    // (it may not relate to the transponder centre freq)
    struct list_head     tuned_freq_list ;
    
    									
    /* program data */
    int                  type;
    int                  p_pid;             // program
    int                  v_pid;             // video
    int                  a_pid;             // audio
    int                  t_pid;             // teletext
    char                 audio[PSI_STR_MAX];
    char                 net[PSI_STR_MAX];
    char                 name[PSI_STR_MAX];

    /* status info */
    int                  updated;
    int                  seen;

    /* hmm ... */
    int                  fd;
};

struct psi_info {
    int                  tsid;

    struct list_head     streams;
    struct list_head     programs;

    /* status info */
    int                  pat_updated;

    /* hmm ... */
    struct psi_program   *pr;
    int                  pat_version;
    int                  sdt_version;
    int                  nit_version;
};

/* ----------------------------------------------------------------------- */

struct ts_packet {
    unsigned int   pid;
    unsigned int   cont;

    unsigned int   tei       :1;
    unsigned int   payload   :1;
    unsigned int   scramble  :2;
    unsigned int   adapt     :2;

    unsigned char  *data;
    unsigned int   size;
};

struct psc_info {
    int                   temp_ref;
    enum ng_video_frame   frame;
    uint64_t              pts;
    int                   gop_seen;
    int                   dec_seq;
    int                   play_seq;
};

struct mpeg_handle {
    int                   fd;

    /* file buffer */
    int                   pgsize;
    unsigned char         *buffer;
    off_t                 boff;
    size_t                bsize;
    size_t                balloc;
    int                   beof;
    int                   slowdown;

    /* error stats */
    int                   errors;
    int                   error_out;

    /* libng format info */
    struct ng_video_fmt   vfmt;
    struct ng_audio_fmt   afmt;
    int                   rate, ratio;

    /* video frame fifo */
    struct list_head      vfifo;
    struct ng_video_buf   *vbuf;

    /* TS packet / PIDs */
    struct ts_packet      ts;
    int                   p_pid;
    int                   v_pid;
    int                   a_pid;

    /* parser state */
    int                   init;
    uint64_t              video_pts;
    uint64_t              video_pts_last;
    uint64_t              audio_pts;
    uint64_t              audio_pts_last;
    off_t                 video_offset;
    off_t                 audio_offset;
    off_t                 init_offset;

    int                   frames;
    int                   gop_seen;
    int                   psc_seen;
    struct psc_info       psc;      /* current picture */
    struct psc_info       pts_ref;
    struct psc_info       gop_ref;
};

/* ----------------------------------------------------------------------- */
// DEBUG
/* ----------------------------------------------------------------------- */

/* ----------------------------------------------------------------------- */
void print_stream(struct psi_stream *stream) ;
void print_program(struct psi_program *program) ;

/* ----------------------------------------------------------------------- */

/* handle psi_* */
struct prog_info* prog_info_get(struct psi_stream *stream, int sid, int alloc) ;
void prog_info_free(struct psi_stream *stream) ;

struct psi_info* psi_info_alloc(void);
void psi_info_free(struct psi_info *info);
struct psi_stream* psi_stream_get(struct psi_info *info, int tsid, int netid, int alloc);
struct psi_stream* psi_stream_newfreq(struct psi_info *info, struct psi_stream* src_stream, int frequency);
struct psi_program* psi_program_get(struct psi_info *info, int tsid,
				    int pnr, int tuned_freq, int alloc);

/* misc */
void hexdump(char *prefix, unsigned char *data, size_t size);
void mpeg_dump_desc(unsigned char *desc, int dlen);

/* common */
unsigned int mpeg_getbits(unsigned char *buf, int start, int count);

struct mpeg_handle* mpeg_init(void);
void mpeg_fini(struct mpeg_handle *h);

unsigned char* mpeg_get_data(struct mpeg_handle *h, off_t pos, size_t size);
size_t mpeg_parse_pes_packet(struct mpeg_handle *h, unsigned char *packet,
			     uint64_t *ts, int *al);
int mpeg_get_audio_rate(unsigned char *header);
int mpeg_get_video_fmt(struct mpeg_handle *h, unsigned char *header);
int mpeg_check_video_fmt(struct mpeg_handle *h, unsigned char *header);
unsigned char* mpeg_find_audio_hdr(unsigned char *buf, int off, int size);

/* program stream */
size_t mpeg_find_ps_packet(struct mpeg_handle *h, int packet, int mask, off_t *pos);

/* transport stream */
void mpeg_parse_psi_string(char *src, int slen, char *dest, int dlen);
int mpeg_parse_psi_pat(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);
int mpeg_parse_psi_pmt(struct psi_program *program, unsigned char *data, int verbose, int tuned_freq);
int mpeg_parse_psi(struct psi_info *info, struct mpeg_handle *h, int verbose, int tuned_freq);
int mpeg_find_ts_packet(struct mpeg_handle *h, int wanted, off_t *pos);

/* DVB stuff */
int mpeg_parse_psi_sdt(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);
int mpeg_parse_psi_nit(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);

#endif
