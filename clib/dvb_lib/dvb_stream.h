#ifndef DVB_STREAM
#define DVB_STREAM

#include <inttypes.h>
#include "dvb_struct.h"

struct multiplex_file_struct {
	int								file;
	time_t 							start;
	time_t 							end;
} ;

struct multiplex_pid_struct {
    struct multiplex_file_struct	 *file_info ;
    unsigned int                     pid;
    unsigned int                     done;
    uint64_t						 errors;
    uint64_t	                     pkts;

    // internal (Perl)
    void							 *ref ;

} ;


/* ----------------------------------------------------------------------- */
int write_stream(struct dvb_state *h, char *filename, int sec) ;

/* ----------------------------------------------------------------------- */
int write_stream_demux(struct dvb_state *h, struct multiplex_pid_struct *pid_list, unsigned num_entries) ;

#endif
