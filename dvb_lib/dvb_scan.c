
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/poll.h>

#include <sys/time.h>
#include <sys/ioctl.h>


#include "dvb_scan.h"


/* ----------------------------------------------------------------------- */
/* ----------------------------------------------------------------------- */
/* maintain current state for these ... */
//char *dvb_src   = NULL;
//char *dvb_lnb   = NULL;
//char *dvb_sat   = NULL;
extern int  dvb_inv;

/* ----------------------------------------------------------------------- */
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



/* ----------------------------------------------------------------------------- */
/* structs & prototypes                                                          */

#define FALSE	0
#define TRUE	!FALSE

struct table {
    struct list_head    next;
    char                *name;
    int                 pid;
    int                 sec;
    int                 fd;
    int                 once;
    int                 done;
};

struct version {
    struct list_head    next;
    char                *name;
    int                 id;
    int                 version;
};

typedef void (*dvbmon_notify)(struct psi_info *info, int event,
			      int tsid, int pnr, void *data);

#define DVBMON_EVENT_SWITCH_TS    1
#define DVBMON_EVENT_UPDATE_TS    2
#define DVBMON_EVENT_UPDATE_PR    3
#define DVBMON_EVENT_DESTROY     99

struct dvbmon* dvbmon_init(struct dvb_state *dvb, int verbose,
			   int o_nit, int o_sdt, int pmts);
void dvbmon_refresh(struct dvbmon* dm);
void dvbmon_add_callback(struct dvbmon* dm, dvbmon_notify func, void *data);
void dvbmon_del_callback(struct dvbmon* dm, dvbmon_notify func, void *data);


struct callback {
    struct list_head    next;
    dvbmon_notify       func;
    void                *data;
};

static void table_add(struct dvbmon *dm, char *name, int pid, int sec,
		      int oneshot);
static void table_open(struct dvbmon *dm, struct table *tab);
static void table_refresh(struct dvbmon *dm, struct table *tab);
static void table_close(struct dvbmon *dm, struct table *tab);
static void table_del(struct dvbmon *dm, int pid, int sec);
static void table_next(struct dvbmon *dm);


/* ----------------------------------------------------------------------- */
// DEBUG
/* ----------------------------------------------------------------------- */

/* ----------------------------------------------------------------------- */
static void print_stream(struct psi_stream *stream)
{

	//    	int                  tsid;
	//
	//        /* network */
	//        int                  netid;
	//        char                 net[PSI_STR_MAX];
	//
	//        int                  frequency;
	//        int                  symbol_rate;
	//        char                 *bandwidth;
	//        char                 *constellation;
	//        char                 *hierarchy;
	//        char                 *code_rate_hp;
	//        char                 *code_rate_lp;
	//        char                 *fec_inner;
	//        char                 *guard;
	//        char                 *transmission;
	//        char                 *polarization;
	//
	//        /* status info */
	//        int                  updated;
	fprintf(stderr, "TSID %d NETID %d : network %s : freq %d : sr %d : BW %s : Const %s : Hier %s : Code rate hp %s lp %s : FEC %s : Guard %s : Tx %s : Pol %s (up %d, tuned %d)\n",
			stream->tsid, stream->netid, stream->net, stream->frequency, stream->symbol_rate,
			stream->bandwidth, stream->constellation, stream->hierarchy, stream->code_rate_hp, stream->code_rate_lp,
			stream->fec_inner, stream->guard, stream->transmission, stream->polarization,
			stream->updated, stream->tuned
	) ;
}

/* ----------------------------------------------------------------------- */
static void print_program(struct psi_program *program)
{

	//        int                  tsid;
	//         int                  pnr;
	//         int                  version;
	//         int                  running;
	//         int                  ca;
	//
	//         /* program data */
	//         int                  type;
	//         int                  p_pid;             // program
	//         int                  v_pid;             // video
	//         int                  a_pid;             // audio
	//         int                  t_pid;             // teletext
	//         char                 audio[PSI_STR_MAX];
	//         char                 net[PSI_STR_MAX];
	//         char                 name[PSI_STR_MAX];
	//
	//         /* status info */
	//         int                  updated;
	//         int                  seen;

	fprintf(stderr, "TSID %d PNR %d : name %s : network %s : running %d : type %d : prog %d, video %d, audio %d, ttext %d : audio %s (up %d / seen %d)\n",
			program->tsid, program->pnr, program->name, program->net, program->running,
			program->type, program->p_pid, program->v_pid, program->a_pid, program->t_pid,
			program->audio,
			program->updated, program->seen
	) ;
}


/* ----------------------------------------------------------------------- */
static void print_streams(struct dvbmon *dvbmon)
{
struct psi_stream *stream;
struct list_head   *item;

	fprintf(stderr, "\n\n\n==STREAMS==\n\n") ;
    list_for_each(item,&dvbmon->info->streams)
    {
    	stream = list_entry(item, struct psi_stream, next);
    	print_stream(stream) ;
    }
}


/* ----------------------------------------------------------------------- */
static void print_programs(struct dvbmon *dvbmon)
{
struct psi_program *program ;
struct list_head   *item;

	fprintf(stderr, "\n==PROGRAMS==\n\n") ;
    list_for_each(item,&dvbmon->info->programs)
    {
        program = list_entry(item, struct psi_program, next);
        print_program(program) ;
    }
}


/* ------------------------------------------------------------------------ */
// CALLBACKS
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */

static int timeout = 20;
static int current;

static void dvbwatch_tty(struct psi_info *info, int event,
			 int tsid, int pnr, void *data)
{
	struct dvbmon *dvbmon = (struct dvbmon *)data ;
    struct psi_program *pr;

    // Uses static global:
    // timeout
    // current


    switch (event)
    {
    case DVBMON_EVENT_SWITCH_TS:
		if (dvbmon->verbose) fprintf(stderr,"  tsid  %5d\n",tsid);
		current = tsid;
		break;
    case DVBMON_EVENT_UPDATE_PR:
		pr = psi_program_get(info, tsid, pnr, 0);
		if (!pr)
			return;
		if (tsid != current)
			return;
		if (pr->type != 1)
			return;
		if (0 == pr->v_pid)
			return;
		if (pr->name[0] == '\0')
			return;

		/* Hmm, get duplicates :-/ */
		if (dvbmon->verbose) fprintf(stderr,"    pnr %5d  %s\n", pr->pnr, pr->name);
    }
}




/* ----------------------------------------------------------------------------- */
// TABLE MANAGEMENT
/* ----------------------------------------------------------------------------- */

/* ----------------------------------------------------------------------------- */
static void table_open(struct dvbmon *dm, struct table *tab)
{
    if (tab->once && dm->tabfds >= dm->tablimit)
	return;

    tab->fd = dvb_demux_req_section(dm->dvb, -1, tab->pid, tab->sec, 0xff,
				    tab->once, dm->timeout);
    if (-1 == tab->fd)
	return;

    dm->tabfds++;

    //    tab->ch  = g_io_channel_unix_new(tab->fd);
    //    tab->id  = g_io_add_watch(tab->ch, G_IO_IN, table_data, dm);
//    tab->id = add_watch(tab->fd, POLLIN, table_data, dm) ;

    if (dm->tabdebug)
	fprintf(stderr,"dvbmon: open:  %s %4d | fd=%d n=%d\n",
		tab->name, tab->pid, tab->fd, dm->tabfds);
}

/* ----------------------------------------------------------------------------- */
static struct table* table_find(struct dvbmon *dm, int pid, int sec)
{
    struct table      *tab;
    struct list_head  *item;

    list_for_each(item,&dm->tables) {
	tab = list_entry(item, struct table, next);
	if (tab->pid == pid && tab->sec == sec)
	    return tab;
    }
    return NULL;
}


/* ----------------------------------------------------------------------------- */
static void table_close(struct dvbmon *dm, struct table *tab)
{
    if (-1 == tab->fd)
	return;

    close(tab->fd);

    tab->fd = -1;
    if (tab->once)
    	tab->done = 1;

    dm->tabfds--;
    if (dm->tabdebug)
	fprintf(stderr,"dvbmon: close: %s %4d | n=%d\n",
		tab->name, tab->pid, dm->tabfds);
}

/* ----------------------------------------------------------------------------- */
static void table_next(struct dvbmon *dm)
{
    struct table      *tab;
    struct list_head  *item;

    list_for_each(item,&dm->tables) {
	tab = list_entry(item, struct table, next);
	if (tab->fd != -1)
	    continue;
	if (tab->done)
	    continue;
	table_open(dm,tab);
	if (dm->tabfds >= dm->tablimit)
	    return;
    }
}

/* ----------------------------------------------------------------------------- */
static void table_add(struct dvbmon *dm, char *name, int pid, int sec,
		      int oneshot)
{
    struct table *tab;

    tab = table_find(dm, pid, sec);
    if (tab)
	return;
    tab = malloc(sizeof(*tab));
    memset(tab,0,sizeof(*tab));
    tab->name = name;
    tab->pid  = pid;
    tab->sec  = sec;
    tab->fd   = -1;
    tab->once = oneshot;
    tab->done = 0;
    list_add_tail(&tab->next,&dm->tables);
    if (dm->tabdebug)
	fprintf(stderr,"dvbmon: add:   %s %4d | sec=0x%02x once=%d\n",
		tab->name, tab->pid, tab->sec, tab->once);

    table_open(dm,tab);
}

/* ----------------------------------------------------------------------------- */
static void table_del(struct dvbmon *dm, int pid, int sec)
{
    struct table      *tab;

    tab = table_find(dm, pid, sec);
    if (NULL == tab)
	return;
    table_close(dm,tab);

    if (dm->tabdebug)
    	fprintf(stderr,"dvbmon: del:   %s %4d\n", tab->name, tab->pid);
    list_del(&tab->next);
    free(tab);
}

/* ----------------------------------------------------------------------------- */
static void table_refresh(struct dvbmon *dm, struct table *tab)
{
    tab->fd = dvb_demux_req_section(dm->dvb, tab->fd, tab->pid,
				    tab->sec, 0xff, 0, dm->timeout);
    if (-1 == tab->fd) {
		fprintf(stderr,"%s: failed\n",__FUNCTION__);
		list_del(&tab->next);
		free(tab);
		return;
    }
}

/* ----------------------------------------------------------------------------- */
static int table_data_seen(struct dvbmon *dm, char *name, int id, int version)
{
    struct version    *ver;
    struct list_head  *item;
    int seen = 0;

    list_for_each(item,&dm->versions) {
		ver = list_entry(item, struct version, next);
	// Dies here because ver => 0x8! i.e. list is corrupt
		if (ver->name == name && ver->id == id) {
			if (ver->version == version)
			seen = 1;
			ver->version = version;
			return seen;
		}
    }
    ver = malloc(sizeof(*ver));
    memset(ver,0,sizeof(*ver));
    ver->name    = name;
    ver->id      = id;
    ver->version = version;
    list_add_tail(&ver->next,&dm->versions);

    return seen;
}

/* ----------------------------------------------------------------------------- */
/* ----------------------------------------------------------------------------- */


/* ----------------------------------------------------------------------------- */
struct dvbmon*
dvbmon_init(struct dvb_state *dvb, int verbose, int o_nit, int o_sdt, int pmts)
{
    struct dvbmon *dm;

    dm = malloc(sizeof(*dm));
    memset(dm,0,sizeof(*dm));
    INIT_LIST_HEAD(&dm->tables);
    INIT_LIST_HEAD(&dm->versions);
    INIT_LIST_HEAD(&dm->callbacks);

    dm->verbose  = verbose;
    dm->tabdebug = 0;
    dm->tablimit = 3 + (o_nit ? 1 : 0) + (o_sdt ? 1 : 0) + pmts;
    dm->timeout  = 60;
    dm->dvb      = dvb;
    dm->info     = psi_info_alloc();
    if (dm->dvb) {
		if (dm->verbose)
			fprintf(stderr,"dvbmon: hwinit ok\n");
		table_add(dm, "pat",   0x00, 0x00, 0);
		table_add(dm, "nit",   0x10, 0x40, 0);
		table_add(dm, "sdt",   0x11, 0x42, 0);
		if (o_nit)
			table_add(dm, "nit",   0x10, 0x41, 0);
		if (o_sdt)
			table_add(dm, "sdt",   0x11, 0x46, 0);
		} else {
		fprintf(stderr,"dvbmon: hwinit FAILED\n");
    }
    return dm;
}

/* ----------------------------------------------------------------------------- */
static void call_callbacks(struct dvbmon* dm, int event, int tsid, int pnr)
{
    struct callback   *cb;
    struct list_head  *item;

    list_for_each(item,&dm->callbacks) {
		cb = list_entry(item, struct callback, next);
		cb->func(dm->info,event,tsid,pnr,cb->data);
    }
}


/* ----------------------------------------------------------------------------- */
void dvbmon_fini(struct dvbmon* dm)
{
    struct list_head  *item, *safe;
    struct version    *ver;
    struct table      *tab;
    struct callback   *cb;

    call_callbacks(dm, DVBMON_EVENT_DESTROY, 0, 0);
    list_for_each_safe(item,safe,&dm->tables) {
		tab = list_entry(item, struct table, next);
		table_del(dm, tab->pid, tab->sec);
    };

    list_for_each_safe(item,safe,&dm->versions) {
		ver = list_entry(item, struct version, next);
		list_del(&ver->next);
		free(ver);
    };

    list_for_each_safe(item,safe,&dm->callbacks) {
        cb = list_entry(item, struct callback, next);
        list_del(&cb->next);
        free(cb);
    };

    psi_info_free(dm->info);
    free(dm);
}

/* ----------------------------------------------------------------------------- */
void dvbmon_refresh(struct dvbmon* dm)
{
    struct list_head  *item;
    struct version    *ver;

    list_for_each(item,&dm->versions) {
		ver = list_entry(item, struct version, next);
		ver->version = PSI_NEW;
    }

}

/* ----------------------------------------------------------------------------- */
void dvbmon_add_callback(struct dvbmon* dm, dvbmon_notify func, void *data)
{
    struct callback *cb;

    cb = malloc(sizeof(*cb));
    memset(cb,0,sizeof(*cb));
    cb->func = func;
    cb->data = data;
    list_add_tail(&cb->next,&dm->callbacks);
}

/* ----------------------------------------------------------------------------- */
void dvbmon_del_callback(struct dvbmon* dm, dvbmon_notify func, void *data)
{
    struct callback   *cb = NULL;
    struct list_head  *item;

    list_for_each(item,&dm->callbacks) {
	cb = list_entry(item, struct callback, next);
	if (cb->func == func && cb->data == data)
	    break;
	cb = NULL;
    }
    if (NULL == cb) {
    	if (dm->verbose) fprintf(stderr,"dvbmon: oops: rm unknown cb %p %p\n",func,data);
	return;
    }
    list_del(&cb->next);
    free(cb);
}


/* ------------------------------------------------------------------------ */
/* ------------------------------------------------------------------------ */
static int table_data(struct dvbmon *dm, struct table *tab, int verbose)
{
struct list_head *item;
struct psi_program *pr;
struct psi_stream *stream;
int id, version, current, old_tsid;
unsigned char buf[4096];

    if (NULL == tab) {
		fprintf(stderr,"dvbmon: invalid table\n");
		return FALSE;
    }

    /* get data */
    if (dvb_demux_get_section(tab->fd, buf, sizeof(buf)) < 0) {
		if (dvb_debug)
			fprintf(stderr,"dvbmon: reading %s failed (frontend not locked?), "
				"fd %d, trying to re-init.\n", tab->name, tab->fd);
		table_refresh(dm,tab);
		return TRUE;
    }
    if (tab->once) {
		table_close(dm,tab);
		table_next(dm);
    }

    id      = mpeg_getbits(buf,24,16);
    version = mpeg_getbits(buf,42,5);
    current = mpeg_getbits(buf,47,1);

    if (dvb_debug)
    {
    	fprintf(stderr, "id 0x%02x : ver=%d curr=%d\n", id, version, current) ;
    	if (verbose)
    	{
        	fprintf(stderr, "TABLE:\n   name %s, pid 0x%02x, sec 0x%02x\n", tab->name, tab->pid, tab->sec) ;
    	}
    }

    if (!current)
    	return TRUE;

    // Skip processing this table iff it's been seen before AND it's not PAT or NIT
    if (table_data_seen(dm, tab->name, id, version) &&
    		0x00 != tab->sec /* pat */&&
    		0x40 != tab->sec /* nit this */ &&
    		0x41 != tab->sec /* nit other */
    )
    {
        if (dvb_debug) fprintf(stderr, "Table seen\n") ;
    	return TRUE;
    }

    switch (tab->sec) {
		case 0x00: /* pat */
			old_tsid = dm->info->tsid;
			mpeg_parse_psi_pat(dm->info, buf, dm->verbose);
			if (old_tsid != dm->info->tsid)
				call_callbacks(dm, DVBMON_EVENT_SWITCH_TS, dm->info->tsid, 0);
			break;

		case 0x02: /* pmt */
			pr = psi_program_get(dm->info, dm->info->tsid, id, 0);
			if (!pr) {
				if (dm->verbose) fprintf(stderr,"dvbmon: 404: tsid %d pid %d\n", dm->info->tsid, id);
				break;
			}
			mpeg_parse_psi_pmt(pr, buf, dm->verbose);
			break;

		case 0x40: /* nit this  */
		case 0x41: /* nit other */
			mpeg_parse_psi_nit(dm->info, buf, dm->verbose);
			break;

		case 0x42: /* sdt this  */
		case 0x46: /* sdt other */
			mpeg_parse_psi_sdt(dm->info, buf, dm->verbose);
			break;

		default:
			if (dm->verbose) fprintf(stderr,"dvbmon: oops: sec=0x%02x\n",tab->sec);
			break;
    }

    /* check for changes */
    if (dm->info->pat_updated) {
		dm->info->pat_updated = 0;
		if (dm->verbose>1)
			fprintf(stderr,"dvbmon: updated: pat\n");
		list_for_each(item,&dm->info->programs) {
			pr = list_entry(item, struct psi_program, next);
			if (!pr->seen)
				table_del(dm, pr->p_pid, 2);
		}
		list_for_each(item,&dm->info->programs) {
			pr = list_entry(item, struct psi_program, next);
			if (pr->seen && pr->p_pid)
				table_add(dm, "pmt", pr->p_pid, 2, 1);
			pr->seen = 0;
		}
    }

    /* inform callbacks */
    list_for_each(item,&dm->info->streams) {
        stream = list_entry(item, struct psi_stream, next);
		if (!stream->updated)
			continue;
		stream->updated = 0;
		call_callbacks(dm, DVBMON_EVENT_UPDATE_TS, stream->tsid, 0);
    }

    list_for_each(item,&dm->info->programs) {
		pr = list_entry(item, struct psi_program, next);

if (dvb_debug)
{
	fprintf(stderr, " + PROG: pnr %d tsid %d type %d name %s net %s : updated %d seen %d\n",
			pr->pnr, pr->tsid, pr->type, pr->name, pr->net, pr->updated, pr->seen) ;
}


		if (!pr->updated)
			continue;
		pr->updated = 0;
//		dvb_lang_parse_audio(pr->audio);
		call_callbacks(dm, DVBMON_EVENT_UPDATE_PR, pr->tsid, pr->pnr);
    }

    return TRUE;
}



/* ------------------------------------------------------------------------ */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
static int dvb_tune_stream(struct dvb_state *dvb, struct psi_stream *stream, int timeout)
{
int rc;

int frequency;
int inversion=0;
int bandwidth=0;
int code_rate_high=0;
int code_rate_low=0;
int modulation=0;
int transmission=0;
int guard_interval=0;
int hierarchy=0;

//fprintf(stderr, "Tuning tsid %d (%s) - FREQ=%d\n", stream->tsid, stream->net, stream->frequency) ;
//print_stream(stream) ;

	// convert params
	frequency = stream->frequency ;

//	if (stream->polarization)
//	{
//		inversion = fe_vdr_bandwidth[ atoi(stream->polarization) ] ;
//	}
	if (stream->bandwidth)
	{
		bandwidth = atoi(stream->bandwidth) ;
	}
	if (stream->code_rate_hp)
	{
		code_rate_high = atoi(stream->code_rate_hp) ;
	}
	if (stream->code_rate_lp)
	{
		code_rate_low = atoi(stream->code_rate_lp) ;
	}
	if (stream->constellation)
	{
		modulation = atoi(stream->constellation) ;
	}
	if (stream->transmission)
	{
		transmission = atoi(stream->transmission) ;
	}
	if (stream->bandwidth)
	{
		guard_interval = atoi(stream->bandwidth) ;
	}
	if (stream->hierarchy)
	{
		hierarchy = atoi(stream->hierarchy) ;
	}

//fprintf(stderr, "TUNE: freq=%d inv=%d bw=%d rate_hi=%d rate_lo=%d mod=%d tx=%d guard=%d hier=%d\n",
//		frequency,
//		inversion,
//		bandwidth,
//		code_rate_high,
//		code_rate_low,
//		modulation,
//		transmission,
//		guard_interval,
//		hierarchy
//		) ;

	// set tuning
	rc = dvb_tune(dvb,
			/* For frontend tuning */
			frequency,
			inversion,
			bandwidth,
			code_rate_high,
			code_rate_low,
			modulation,
			transmission,
			guard_interval,
			hierarchy,
			timeout) ;

	return (rc) ;
}

/* ------------------------------------------------------------------------ */
static void tty_scan(struct dvb_state *dvb, struct dvbmon *dvbmon)
{
time_t tuned;
//char *sec;
char *name;
int num_freqs ;

int ready ;
int i ;
int rc ;

int nfds=0 ; // TODO: just use dvbmon->tabfds
struct pollfd *pollfds;
struct table *tab = NULL;
struct table **table_list = NULL;

struct list_head   *item;
struct psi_stream *stream;

// Uses static global:
// timeout
// current

    // Prepare for polling
    pollfds = (struct pollfd* )malloc(sizeof(struct pollfd) * dvbmon->tablimit);
    memset(pollfds, 0, sizeof(struct pollfd) * dvbmon->tablimit) ;

    table_list = (struct table** )malloc(sizeof(struct table *) * dvbmon->tablimit);
    memset(table_list, 0, sizeof(struct table *) * dvbmon->tablimit) ;

	// start
    for (num_freqs=1;num_freqs;)
    {
		current = 0;

		if (dvbmon->verbose>1) fprintf(stderr,"about to poll ..\n");

		/* fish data */
		tuned = time(NULL);
		while (time(NULL) - tuned < timeout)
		{
			if (dvbmon->verbose>1) fprintf(stderr,"Polling for data ...\n");

			// Get latest poll info
			memset(pollfds, 0, sizeof(struct pollfd) * dvbmon->tablimit) ;
			memset(table_list, 0, sizeof(struct table *) * dvbmon->tablimit) ;
			nfds=0 ;
			list_for_each(item, &dvbmon->tables)
			{
				tab = list_entry(item, struct table, next);
				if (tab && (tab->fd>0) )
				{
					pollfds[nfds].fd = tab->fd ;
					pollfds[nfds].events = POLLIN ;
					pollfds[nfds].revents = 0 ;

					table_list[nfds] = tab ;

					++nfds ;
				}
			}

			// poll
			ready = poll(pollfds, nfds, timeout);

			if (dvbmon->verbose>1) fprintf(stderr," + ready=%d\n", ready);

			if (ready > 0)
			{
				// Check each fd
				for(i=0; i<nfds; i++)
				{
					if (dvbmon->verbose>1) fprintf(stderr," %d : revents=%d\n", i, pollfds[i].revents);

					if (pollfds[i].revents == POLLIN)
					{
						if (dvbmon->verbose>2) fprintf(stderr," + dispatch..\n");

						// fd is ready so dispatch
						table_data(dvbmon, table_list[i], dvbmon->verbose) ;
					}
				}
			}
		}

		if (dvbmon->verbose>1) fprintf(stderr,"done while loop ..\n");

		if (!current)
		{
			if (dvbmon->verbose) fprintf(stderr,"Hmm, no data received. Frontend is%s locked.\n",
										dvb_frontend_is_locked(dvb) ? "" : " not");
		}

//		fprintf(stderr, "\n\n----------------------------------------------------\nStreams so far:\n") ;
//	    print_streams(dvbmon) ;
//		fprintf(stderr, "\nStreams so far\n----------------------------------------------------\n\n") ;

		num_freqs=0;
	    list_for_each(item,&dvbmon->info->streams)
	    {
	    	stream = list_entry(item, struct psi_stream, next);

	    	// Find next freq to select (if any left)
	    	if (!stream->tuned)
	    	{
	    		// tune first
	    		if (num_freqs==0)
	    		{
	    			stream->tuned=1 ;
					if (dvbmon->verbose) fprintf(stderr, "Tuning tsid %d (%s)\n", stream->tsid, stream->net) ;

					rc = dvb_tune_stream(dvb, stream, 100) ;

					if (rc != 0 )
					{
						if (dvbmon->verbose) fprintf(stderr, " Tuning failed\n") ;
						break ;
					}
	    		}

	    		// keep track of total number of freqs left to tune
	    		++num_freqs ;
	    	}
	    }


//fprintf(stderr, "# freqs left = %d\n", num_freqs) ;

    }

    // Clean up
    free(table_list) ;
    free(pollfds) ;
}

/* ----------------------------------------------------------------------- */
struct dvbmon *dvb_scan_freqs(struct dvb_state *dvb, int verbose)
{
struct dvbmon *dvbmon ;
struct psi_program *program ;
struct psi_stream *stream;
struct list_head   *item;


	// Initialise the monitor
    dvbmon = dvbmon_init(dvb, verbose, /* other NIT */ 1,  /* other SDT */ 1, /* # PMTs */ 2);

	// set up scanning callback handler
	dvbmon_add_callback(dvbmon,dvbwatch_tty, dvbmon);

	// do scan
	tty_scan(dvb, dvbmon);

	// return results
	return dvbmon ;
}

