#ifndef DVB_TUNING
#define DVB_TUNING


#include "dvb_struct.h"

int
xioctl(int fd, int cmd, void *arg, int mayfail);
int dvb_frontend_open(struct dvb_state *h, int write);


/* ----------------------------------------------------------------------- */

int dvb_tune(struct dvb_state *h,
		int frequency,
		int inversion,
		int bandwidth,
		int code_rate_high,
		int code_rate_low,
		int modulation,
		int transmission,
		int guard_interval,
		int hierarchy,

		int timeout
) ;

int dvb_select_channel(struct dvb_state *h,
		int frequency,
		int inversion,
		int bandwidth,
		int code_rate_high,
		int code_rate_low,
		int modulation,
		int transmission,
		int guard_interval,
		int hierarchy,

		int vpid,
		int apid,

		int sid
) ;

void dvb_frontend_release(struct dvb_state *h, int write);
int dvb_frontend_tune(struct dvb_state *h,
		int frequency,
		int inversion,
		int bandwidth,
		int code_rate_high,
		int code_rate_low,
		int modulation,
		int transmission,
		int guard_interval,
		int hierarchy
);
int dvb_frontend_is_locked(struct dvb_state *h);
int dvb_frontend_wait_lock(struct dvb_state *h, int timeout);
int dvb_finish_tune(struct dvb_state *h, int timeout);
int dvb_finish_tune(struct dvb_state *h, int timeout);

/* ======================================================================= */
/* handle dvb demux                                                        */

void dvb_demux_filter_setup(struct dvb_state *h, int video, int audio);
int dvb_demux_filter_apply(struct dvb_state *h);
void dvb_demux_filter_release(struct dvb_state *h);
int dvb_demux_get_section(int fd, unsigned char *buf, int len) ;
//int dvb_demux_req_section(struct dvb_state *h, int pid, int timeout)
int dvb_demux_req_section(struct dvb_state *h, int fd, int pid,
			  int sec, int mask, int oneshot, int timeout) ;

/* ======================================================================= */
/* handle dvb dvr                                                          */

int dvb_dvr_open(struct dvb_state *h) ;
int dvb_dvr_release(struct dvb_state *h) ;

/* ======================================================================= */
/* open/close/tune dvb devices                                             */

struct dvb_state* dvb_init(char *adapter, int frontend);
struct dvb_state* dvb_init_nr(int adapter, int frontend);
void dvb_fini(struct dvb_state *h);

#endif
