/*
 * handle dvb devices
 * import vdr channels.conf files
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>

#include <sys/time.h>
#include <sys/ioctl.h>

#include "dvb_debug.h"
#include "dvb_tune.h"

int dvb_type_override = -1;


/* maintain current state for these ... */
char *dvb_src   = NULL;
char *dvb_lnb   = NULL;
char *dvb_sat   = NULL;
int  dvb_inv    = INVERSION_AUTO;

/* ======================================================================= */
/* map vdr config file numbers to enums                                    */

#define VDR_MAX 999

static fe_bandwidth_t fe_vdr_bandwidth[] = {
    [ 0 ... VDR_MAX ] = BANDWIDTH_AUTO,
    [ 8 ]             = BANDWIDTH_8_MHZ,
    [ 7 ]             = BANDWIDTH_7_MHZ,
    [ 6 ]             = BANDWIDTH_6_MHZ,
};

static fe_code_rate_t fe_vdr_rates[] = {
    [ 0 ... VDR_MAX ] = FEC_AUTO,
    [ 12 ]            = FEC_1_2,
    [ 23 ]            = FEC_2_3,
    [ 34 ]            = FEC_3_4,
    [ 45 ]            = FEC_4_5,
    [ 56 ]            = FEC_5_6,
    [ 67 ]            = FEC_6_7,
    [ 78 ]            = FEC_7_8,
    [ 89 ]            = FEC_8_9,
};

static fe_modulation_t fe_vdr_modulation[] = {
    [ 0 ... VDR_MAX ] = QAM_AUTO,
    [  16 ]           = QAM_16,
    [  32 ]           = QAM_32,
    [  64 ]           = QAM_64,
    [ 128 ]           = QAM_128,
    [ 256 ]           = QAM_256,
#ifdef FE_ATSC
    [   8 ]           = VSB_8,
    [   1 ]           = VSB_16,
#endif
};

static fe_transmit_mode_t fe_vdr_transmission[] = {
    [ 0 ... VDR_MAX ] = TRANSMISSION_MODE_AUTO,
    [ 2 ]             = TRANSMISSION_MODE_2K,
    [ 8 ]             = TRANSMISSION_MODE_8K,
};

static fe_guard_interval_t fe_vdr_guard[] = {
    [ 0 ... VDR_MAX ] = GUARD_INTERVAL_AUTO,
    [  4 ]            = GUARD_INTERVAL_1_4,
    [  8 ]            = GUARD_INTERVAL_1_8,
    [ 16 ]            = GUARD_INTERVAL_1_16,
    [ 32 ]            = GUARD_INTERVAL_1_32,
};

static fe_hierarchy_t fe_vdr_hierarchy[] = {
    [ 0 ... VDR_MAX ] = HIERARCHY_AUTO,
    [ 0 ]             = HIERARCHY_NONE,
    [ 1 ]             = HIERARCHY_1,
    [ 2 ]             = HIERARCHY_2,
    [ 4 ]             = HIERARCHY_4,
};


/* ----------------------------------------------------------------------- */
/*
 * Set up a channel  ready for record
 */
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
)
{
	int rc=0 ;

	rc = dvb_frontend_tune(h,
		frequency,
		inversion,
		bandwidth,
		code_rate_high,
		code_rate_low,
		modulation,
		transmission,
		guard_interval,
		hierarchy
	);
	if (rc != 0) return rc ;

	rc = dvb_wait_tune(h, timeout) ;
	if (rc != 0) return rc ;

	return rc ;
}

#ifdef NOTUSED
/* ----------------------------------------------------------------------- */
/*
 * Set up a channel  ready for record
 */
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
)
{
	int rc=0 ;

	rc = dvb_frontend_tune(h,
		frequency,
		inversion,
		bandwidth,
		code_rate_high,
		code_rate_low,
		modulation,
		transmission,
		guard_interval,
		hierarchy
	);
	if (rc != 0) return rc ;

	dvb_demux_filter_setup(h, vpid, apid) ;

	rc = dvb_finish_tune(h,100);
	if (rc != 0) return rc ;

	return rc ;
}
#endif


/* ======================================================================= */
/* handle diseqc                                                           */

/* ----------------------------------------------------------------------- */
int
xioctl(int fd, int cmd, void *arg, int mayfail)
{
    int rc;

    rc = ioctl(fd,cmd,arg);

    if (0 == rc && !dvb_debug)
	return rc;
    if (mayfail && errno == mayfail && !dvb_debug)
	return rc;

/* FIX
    print_ioctl(stderr,ioctls_dvb,"dvb ioctl: ",cmd,arg);
*/

    fprintf(stderr,": %s\n",(rc == 0) ? "ok" : strerror(errno));
    return rc;
}

/* ======================================================================= */
/* handle dvb frontend                                                     */

/* ----------------------------------------------------------------------- */
//static
int dvb_frontend_open(struct dvb_state *h, int write)
{
	char *_name="dvb_frontend_open" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Open %s\n", write ? "write" : "read-only");}

	int *fd = write ? &h->fdwr : &h->fdro;

    if (-1 != *fd)
    {
    	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Already got fd=%d\n", *fd);}
    	if (dvb_debug>1) _fn_end(_name, 0) ;
    	return 0;
    }

    *fd = open(h->frontend, (write ? O_RDWR : O_RDONLY) | O_NONBLOCK);

    if (-1 == *fd) {
	fprintf(stderr,"dvb fe: open %s: %s\n",
		h->frontend,strerror(errno));
	if (dvb_debug>1) _fn_end(_name, -1) ;
	return -10;
    }
	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Created fd=%d\n", *fd);}
	if (dvb_debug>1) _fn_end(_name, 0) ;
    return 0;
}

/* ----------------------------------------------------------------------- */
void dvb_frontend_release(struct dvb_state *h, int write)
{
    int *fd = write ? &h->fdwr : &h->fdro;

    if (-1 != *fd) {
	close(*fd);
	*fd = -1;
    }
}

/* ----------------------------------------------------------------------- */
static void fixup_numbers(struct dvb_state *h, int lof)
{
    switch (h->info.type) {
    case FE_QPSK:
	/*
	 * DVB-S
	 *   - kernel API uses kHz here.
	 *   - /etc/vdr/channel.conf + diseqc.conf use MHz
	 *   - scan (from linuxtv.org dvb utils) uses KHz
	 */
        if (lof < 1000000)
	    lof *= 1000;
        if (h->p.frequency < 1000000)
	    h->p.frequency *= 1000;
	h->p.frequency -= lof;
	if (h->p.u.qpsk.symbol_rate < 1000000)
	    h->p.u.qpsk.symbol_rate *= 1000;
	break;
    case FE_QAM:
    case FE_OFDM:
#ifdef FE_ATSC
    case FE_ATSC:
#endif
	/*
	 * DVB-C,T
	 *   - kernel API uses Hz here.
	 *   - /etc/vdr/channel.conf allows Hz, kHz and MHz
	 */
	if (h->p.frequency < 1000000)
	    h->p.frequency *= 1000;
	if (h->p.frequency < 1000000)
	    h->p.frequency *= 1000;
	break;
    }
}


/* ----------------------------------------------------------------------- */
/* int dvb_frontend_tune(struct dvb_state *h, char *domain, char *section) */
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
)
{
char *_name="dvb_frontend_tune" ;
if (dvb_debug>1) _fn_start(_name) ;
    char *diseqc;
    char *action;
    int lof = 0;
    int val;
    int rc;

    if (-1 == dvb_frontend_open(h,1))
    {
		fprintf(stderr,"unable to open frontend\n");
    	if (dvb_debug>1) _fn_end(_name, -1) ;

    	return -11;
    }

    if (dvb_src)
    	free(dvb_src);
    if (dvb_lnb)
    	free(dvb_lnb);
    if (dvb_sat)
    	free(dvb_sat);
    dvb_src = NULL;
    dvb_lnb = NULL;
    dvb_sat = NULL;

if (dvb_debug>1) _dump_state(_name, "at start", h) ;


   	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "OFDM\n") ; }

	h->p.frequency = frequency;
	h->p.inversion = inversion;

/*
	h->p.u.ofdm.bandwidth = fe_vdr_bandwidth [ bandwidth ];
	h->p.u.ofdm.code_rate_HP = fe_vdr_rates [ code_rate_high ];
	h->p.u.ofdm.code_rate_LP = fe_vdr_rates [ code_rate_low ];
	h->p.u.ofdm.constellation = fe_vdr_modulation [ modulation ];
	h->p.u.ofdm.transmission_mode = fe_vdr_transmission [ transmission ];
	h->p.u.ofdm.guard_interval = fe_vdr_guard [ guard_interval ];
	h->p.u.ofdm.hierarchy_information = fe_vdr_hierarchy [ hierarchy ];
*/

	/* Raw numbers passed in */
	h->p.u.ofdm.bandwidth = bandwidth ;
	h->p.u.ofdm.code_rate_HP = code_rate_high ;
	h->p.u.ofdm.code_rate_LP = code_rate_low ;
	h->p.u.ofdm.constellation = modulation ;
	h->p.u.ofdm.transmission_mode = transmission ;
	h->p.u.ofdm.guard_interval = guard_interval ;
	h->p.u.ofdm.hierarchy_information = hierarchy ;

if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "fixup_numbers(h, lof=%d)\n", lof) ; }
    fixup_numbers(h,lof);

    if (0 == memcmp(&h->p, &h->plast, sizeof(h->plast))) {
		if (dvb_frontend_is_locked(h)) {
		    /* same frequency and frontend still locked */
		    if (dvb_debug)
			fprintf(stderr,"dvb fe: skipped tuning\n");
		    rc = 0;
		    goto done;
		}
    }

    /*
    dvb_src = NULL;
    dvb_lnb = NULL;
    dvb_sat = NULL;
	*/
if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "dvb_src=%s, dvb_lnb=%s, dvb_sat=%s\n", dvb_src, dvb_lnb, dvb_sat) ; }
if (dvb_debug>1) _dump_state(_name, "before ioctl call", h) ;

    rc = -1;
if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "xiotcl(FE_SET_FRONTEND)\n") ; }
    if (-1 == xioctl(h->fdwr,FE_SET_FRONTEND,&h->p, 0)) {
		dump_fe_info(h);
		goto done;
    }

    if (dvb_debug)
    	dump_fe_info(h);

    memcpy(&h->plast, &h->p, sizeof(h->plast));
    rc = 0;

done:

if (dvb_debug>1) _fn_end(_name, rc) ;

    // Hmm, the driver seems not to like that :-/
    // dvb_frontend_release(h,1);
    return rc;
}

/* ----------------------------------------------------------------------- */
int dvb_frontend_is_locked(struct dvb_state *h)
{
    fe_status_t  status  = 0;

    if (-1 == ioctl(h->fdro, FE_READ_STATUS, &status)) {
	perror("dvb fe: ioctl FE_READ_STATUS");
	return 0;
    }
    return (status & FE_HAS_LOCK);
}

/* ----------------------------------------------------------------------- */
int dvb_frontend_wait_lock(struct dvb_state *h, int timeout)
{
    struct timeval start,now,tv;
    int msec,locked = 0, runs = 0;

    gettimeofday(&start,NULL);
/* Fix
    if (dvb_debug)
	dvb_frontend_status_title();
*/
    for (;;) {
	tv.tv_sec  = 0;
	tv.tv_usec = 33 * 1000;
	select(0,NULL,NULL,NULL,&tv);
/* Fix
	if (dvb_debug)
	    dvb_frontend_status_print(h);
*/
	if (dvb_frontend_is_locked(h))
	    locked++;
	else
	    locked = 0;
	if (locked > 3)
	    return 0;
	runs++;

	gettimeofday(&now,NULL);
	msec  = (now.tv_sec - start.tv_sec) * 1000;
	msec += now.tv_usec/1000;
	msec -= start.tv_usec/1000;
	if (msec > timeout && runs > 3)
	    break;
    }
    return -12;
}

/* ======================================================================= */
/* handle dvb demux                                                        */

/* ----------------------------------------------------------------------- */
void dvb_demux_filter_setup(struct dvb_state *h, int video, int audio)
{
	char *_name="dvb_demux_filter_setup" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "vidfeo=%d, audio=%d\n", video, audio); }

	h->video.filter.pid      = video;
    h->video.filter.input    = DMX_IN_FRONTEND;
    h->video.filter.output   = DMX_OUT_TS_TAP;
    h->video.filter.pes_type = DMX_PES_VIDEO;
    h->video.filter.flags    = 0;

    h->audio.filter.pid      = audio;
    h->audio.filter.input    = DMX_IN_FRONTEND;
    h->audio.filter.output   = DMX_OUT_TS_TAP;
    h->audio.filter.pes_type = DMX_PES_AUDIO;
    h->audio.filter.flags    = 0;

	if (dvb_debug>1) _dump_state(_name, "", h);
	if (dvb_debug>1) _fn_end(_name, 0) ;
}

/* ----------------------------------------------------------------------- */
int dvb_demux_filter_apply(struct dvb_state *h)
{
	char *_name="dvb_demux_filter_apply" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) _dump_state(_name, "", h);

	if (0 != h->video.filter.pid) {
	/* setup video filter */
	if (-1 == h->video.fd) {
	    h->video.fd = open(h->demux,O_RDWR);
	    if (-1 == h->video.fd) {
		fprintf(stderr,"dvb mux: [video] open %s: %s\n",
			h->demux,strerror(errno));
		goto oops;
	    }
	}
	if (-1 == xioctl(h->video.fd,DMX_SET_PES_FILTER,&h->video.filter,0)) {
	    fprintf(stderr,"dvb mux: [video] ioctl DMX_SET_PES_FILTER: %s\n",
		    strerror(errno));
	    goto oops;
	}
    } else {
	/* no video */
	if (-1 != h->video.fd) {
	    close(h->video.fd);
	    h->video.fd = -1;
	}
    }

    if (0 != h->audio.filter.pid) {
	/* setup audio filter */
	if (-1 == h->audio.fd) {
	    h->audio.fd = open(h->demux,O_RDWR);
	    if (-1 == h->audio.fd) {
		fprintf(stderr,"dvb mux: [audio] open %s: %s\n",
			h->demux,strerror(errno));
		goto oops;
	    }
	}
	if (-1 == xioctl(h->audio.fd,DMX_SET_PES_FILTER,&h->audio.filter,0)) {
	    fprintf(stderr,"dvb mux: [audio] ioctl DMX_SET_PES_FILTER: %s\n",
		    strerror(errno));
	    goto oops;
	}
    } else {
	/* no audio */
	if (-1 != h->audio.fd) {
	    close(h->audio.fd);
	    h->audio.fd = -1;
	}
    }

    if (-1 != h->video.fd) {
	if (-1 == xioctl(h->video.fd,DMX_START,NULL,0)) {
	    perror("dvb mux: [video] ioctl DMX_START");
	    goto oops;
	}
    }
    if (-1 != h->audio.fd) {
	if (-1 == xioctl(h->audio.fd,DMX_START,NULL,0)) {
	    perror("dvb mux: [audio] ioctl DMX_START");
	    goto oops;
	}
    }

/*
    ng_mpeg_vpid = h->video.filter.pid;
    ng_mpeg_apid = h->audio.filter.pid;
    if (dvb_debug)
	fprintf(stderr,"dvb mux: dvb ts pids: video=%d audio=%d\n",
		ng_mpeg_vpid,ng_mpeg_apid);
*/

	if (dvb_debug>1) _fn_end(_name, 0) ;
    return 0;

 oops:
		if (dvb_debug>1) _fn_end(_name, -1) ;
    return -13;
}

/* ----------------------------------------------------------------------- */
void dvb_demux_filter_release(struct dvb_state *h)
{
    if (-1 != h->audio.fd) {
	xioctl(h->audio.fd,DMX_STOP,NULL,0);
	close(h->audio.fd);
	h->audio.fd = -1;
    }
    if (-1 != h->video.fd) {
	xioctl(h->video.fd,DMX_STOP,NULL,0);
	close(h->video.fd);
	h->video.fd = -1;
    }
/*
    ng_mpeg_vpid = 0;
    ng_mpeg_apid = 0;
*/
}



/* ----------------------------------------------------------------------- */
int dvb_demux_get_section(int fd, unsigned char *buf, int len)
{
    int rc;

    memset(buf,0,len);
    if ((rc = read(fd, buf, len)) < 0)
	if ((ETIMEDOUT != errno && EOVERFLOW != errno) || dvb_debug)
	    fprintf(stderr,"dvb mux: read: %s [%d]\n",
		    strerror(errno), errno);
    return rc;
}


/* ----------------------------------------------------------------------- */

int dvb_demux_req_section(struct dvb_state *h, int fd, int pid,
			  int sec, int mask, int oneshot, int timeout)
{
/*
int fd = -1 ;
int oneshot = 1 ;
int sec = 2 ;
int mask = 0xff ;
*/

	char *_name="dvb_demux_req_section" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "fd=%d pid=%d sec=%d mask=%d oneshot=%d timeout=%d\n", fd, pid, sec, mask, oneshot, timeout); }


	struct dmx_sct_filter_params filter;

    memset(&filter,0,sizeof(filter));
    filter.pid              = pid;
    filter.filter.filter[0] = sec;
    filter.filter.mask[0]   = mask;
    filter.timeout          = timeout * 1000;
    filter.flags            = DMX_IMMEDIATE_START | DMX_CHECK_CRC;
    if (oneshot)
    	filter.flags       |= DMX_ONESHOT;

    if (-1 == fd) {
    	fd = open(h->demux, O_RDWR);
	if (-1 == fd) {
	    fprintf(stderr,"dvb mux: [pid %d] open %s: %s\n",
		    pid, h->demux, strerror(errno));
	    goto oops;
	}
    }
    if (-1 == xioctl(fd, DMX_SET_FILTER, &filter, 0)) {
    	fprintf(stderr,"dvb mux: [pid %d] ioctl DMX_SET_PES_FILTER: %s\n",
		pid, strerror(errno));
	goto oops;
    }

	if (dvb_debug>1) _fn_end(_name, 0) ;
    return fd;

 oops:
    if (-1 != fd)
    	close(fd);

	if (dvb_debug>1) _fn_end(_name, -1) ;
    return -14;
}

/* ======================================================================= */
/* open/close/tune dvr                                                     */

/* ----------------------------------------------------------------------- */
int dvb_dvr_open(struct dvb_state *h)
{
	char *_name="dvb_dvr_open" ;
	if (dvb_debug>1) _fn_start(_name) ;

	int rc=0;

	if (-1 == h->dvro)
	{
		h->dvro = open(h->dvr,  O_RDONLY) ;
		if (-1 == h->dvro)
		{
			fprintf(stderr,"error opening dvr0: %s\n", strerror(errno));
			rc=-1 ;
		}
	}

	if (dvb_debug>5) _dump_state(_name, "", h);
	if (dvb_debug>1) _fn_end(_name, rc) ;
	return rc ;
}

/* ----------------------------------------------------------------------- */
int dvb_dvr_release(struct dvb_state *h)
{
    if (-1 != h->dvro)
    {
		close(h->dvro);
		h->dvro = -1;
    }

    return 0 ;
}


/* ======================================================================= */
/* open/close/tune dvb devices                                             */

/* ----------------------------------------------------------------------- */
void dvb_fini(struct dvb_state *h)
{
	char *_name="dvb_fini" ;
	if (dvb_debug>1) _fn_start(_name) ;

    dvb_frontend_release(h,1);
    dvb_frontend_release(h,0);
    dvb_demux_filter_release(h);
    dvb_dvr_release(h);
    free(h);

	if (dvb_debug>1) _fn_end(_name, 0) ;
}

/* ----------------------------------------------------------------------- */
struct dvb_state* dvb_init(char *adapter, int frontend)
{
	char *_name="dvb_init" ;
	if (dvb_debug>1) _fn_start(_name) ;

	struct dvb_state *h;

    h = malloc(sizeof(*h));
    if (NULL == h)
	goto oops;
    memset(h,0,sizeof(*h));
    h->fdro     = -1;
    h->fdwr     = -1;
    h->dvro     = -1;
    h->audio.fd = -1;
    h->video.fd = -1;

    snprintf(h->frontend, sizeof(h->frontend),"%s/frontend%d", adapter, frontend);
    snprintf(h->demux,    sizeof(h->demux),   "%s/demux%d",    adapter, frontend);
    snprintf(h->dvr,      sizeof(h->demux),   "%s/dvr%d",      adapter, frontend);

    if (0 != dvb_frontend_open(h,0))
	goto oops;

    if (-1 == xioctl(h->fdro, FE_GET_INFO, &h->info, 0)) {
	perror("dvb fe: ioctl FE_GET_INFO");
	goto oops;
    }

    /* hacking DVB-S without hardware ;) */
    if (-1 != dvb_type_override)
	h->info.type = dvb_type_override;
	if (dvb_debug>1) _fn_end(_name, 0) ;
    return h;

 oops:
    if (h)
	dvb_fini(h);
	if (dvb_debug>1) _fn_end(_name, -1) ;
    return NULL;
}

/* ----------------------------------------------------------------------- */
struct dvb_state* dvb_init_nr(int adapter, int frontend)
{
	char *_name="dvb_init_nr" ;
	if (dvb_debug>1) _fn_start(_name) ;

	char path[32];

    snprintf(path,sizeof(path),"/dev/dvb/adapter%d",adapter);
	if (dvb_debug>1) _fn_end(_name, 0) ;
    return dvb_init(path, frontend);
}




/* ----------------------------------------------------------------------- */
int dvb_wait_tune(struct dvb_state *h, int timeout)
{
	char *_name="dvb_wait_tune" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) _dump_state(_name, "", h);

	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Ensure frontend locked\n"); }
    if (0 == timeout)
    {
		if (!dvb_frontend_is_locked(h))
		{
			if (dvb_debug>1) _fn_end(_name, -1) ;
		    return -15;
		}
    }
    else
    {
		if (0 != dvb_frontend_wait_lock(h, timeout))
		{
			if (dvb_debug>1) _fn_end(_name, -1) ;
		    return -16;
		}
    }

	if (dvb_debug>1) _fn_end(_name, 0) ;
    return 0;
}


/* ----------------------------------------------------------------------- */
int dvb_finish_tune(struct dvb_state *h, int timeout)
{
	char *_name="dvb_finish_tune" ;
	if (dvb_debug>1) _fn_start(_name) ;
	if (dvb_debug>1) _dump_state(_name, "", h);

	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Ensure video & audio filters are initialised\n"); }
	if (0 == h->video.filter.pid && 0 == h->audio.filter.pid)
	{
		if (dvb_debug>1) _fn_end(_name, -2) ;
		return -20;
	}

	// Ensure frontend is tuned
	int rc = dvb_wait_tune(h, timeout) ;
	if (rc != 0) return rc ;


	if (dvb_debug>1) {_prt_indent(_name) ; fprintf(stderr, "Apply filter\n"); }
    if (0 != dvb_demux_filter_apply(h))
    {
    	if (dvb_debug>1) _fn_end(_name, -2) ;
    	return -21;
    }

	if (dvb_debug>1) _fn_end(_name, 0) ;
    return 0;
}

