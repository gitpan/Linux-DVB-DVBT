/*
 * MPEG1/2 transport and program stream parser and demuxer code.
 *
 * (c) 2003 Gerd Knorr <kraxel@bytesex.org>
 *
 */
#ifndef PARSE_MPEG
#define PARSE_MPEG

#include <inttypes.h>
#include "list.h"

extern char *psi_charset[0x20];
extern char *psi_service_type[0x100];

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
    
	// keep a record of the currently tuned frequency when we saw this
    // (it may not relate to the transponder centre freq)
    struct list_head     tuned_freq_list ;
    
    									
    /* program data */
    int                  type;
    int                  p_pid;             // program
    int                  v_pid;             // video
    int                  a_pid;             // audio
    int                  t_pid;             // teletext
    int                  s_pid;             // subtitle
    int                  pcr_pid;           // PCR (program clock reference)
    char                 audio[PSI_STR_MAX];
    char                 net[PSI_STR_MAX];
    char                 name[PSI_STR_MAX];

    /* status info */
    int                  updated;
    int                  seen;

    /* hmm ... */
//    int                  fd;
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

/* transport stream */
void mpeg_parse_psi_string(char *src, int slen, char *dest, int dlen);
int mpeg_parse_psi_pat(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);
int mpeg_parse_psi_pmt(struct psi_program *program, unsigned char *data, int verbose, int tuned_freq);

/* DVB stuff */
int mpeg_parse_psi_sdt(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);
int mpeg_parse_psi_nit(struct psi_info *info, unsigned char *data, int verbose, int tuned_freq);

#endif
