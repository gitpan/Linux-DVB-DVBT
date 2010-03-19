#ifndef DVB_STREAM
#define DVB_STREAM

#include "dvb_struct.h"

//struct multiplex_record_struct {
//    char                             *filename;
//    unsigned int                     duration_secs;
//    unsigned int                     offset_secs;
//
//    /* list of pids */
//    int                              num_pids;
//    unsigned int                     *pids;
//} ;

struct multiplex_file_struct {
	int								file;
	time_t 							start;
	time_t 							end;
} ;

struct multiplex_pid_struct {
    struct multiplex_file_struct	 *file_info ;
    unsigned int                     pid;
    unsigned int                     done;

    // debug
    unsigned int                     pkts;
} ;


/* ----------------------------------------------------------------------- */
int write_stream(struct dvb_state *h, char *filename, int sec) ;

/* ----------------------------------------------------------------------- */
int write_stream_demux(struct dvb_state *h, struct multiplex_pid_struct *pid_list, unsigned num_entries) ;

#endif
