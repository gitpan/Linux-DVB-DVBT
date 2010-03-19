#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/*---------------------------------------------------------------------------------------------------*/
#include <linux/dvb/frontend.h>
#include <linux/dvb/dmx.h>

#include "list.h"

#include "dvb_lib/dvb_struct.h"
#include "dvb_lib/dvb_lib.h"

#define DVBT_VERSION		"1.11"
#define DEFAULT_TIMEOUT		900

// If large file support is not included, then make the value do nothing
#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

/*---------------------------------------------------------------------------------------------------*/

/** ARRAY store macros **/

#define AVS_H(arr, h)				av_push(arr, newRV((SV *)h))
#define AVS_A(arr, a)				av_push(arr, newRV((SV *)a))
#define AVS_I(arr, i)				av_push(arr, newSViv(i))
#define AVS_S(arr, s)				av_push(arr, newSVpv(s, 0))


/** HASH store macros **/

/* Use 'name' as structure field name AND HASH key name */
#define HVS(h, name, sv)		hv_store(h, #name, sizeof(#name)-1, sv, 0)
#define HVS_S(h, sp, name)		if (sp->name)      hv_store(h, #name, sizeof(#name)-1, newSVpv(sp->name, 0), 0)
#define HVS_I(h, sp, name)		if (sp->name >= 0) hv_store(h, #name, sizeof(#name)-1, newSViv(sp->name), 0)
#define HVS_BIT(h, var, name)	hv_store(h, #name, sizeof(#name)-1, newSViv(var & name ? 1 : 0), 0)

#define HVS_INT(h, name, i)		hv_store(h, #name, sizeof(#name)-1, newSViv(i), 0)

/* Specify the structure field name and HASH key name separately */
#define HVSN_S(h, sp, name, key)		if (sp->name)      hv_store(h, #key, sizeof(#key)-1, newSVpv(sp->name, 0), 0)
#define HVSN_I(h, sp, name, key)		if (sp->name >= 0) hv_store(h, #key, sizeof(#key)-1, newSViv(sp->name), 0)

/* Convert string before storing in hash */
#define HVS_STRING(h, sp, name)		hv_store(h, #name, sizeof(#name)-1, newSVpv(_to_string(sp->name), 0), 0)

/** HASH read macros **/
#define HVF_I(hv,var)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      var = SvIV (*val); \
  	  if (DVBT_DEBUG) fprintf(stderr, " set %s = %d\n", #var, var); \
  	} \
  }

#define HVF(hv, var)	hv_fetch (hv, #var, sizeof (#var) - 1, 0)


/* get the HASH ref using the specified key. If not currently set, then create a new HASH and add it to the parent */
#define GET_HREF(hv, key, var)                                \
  if ( (val = hv_fetch (hv, #key, sizeof (#key) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      var = (HV *)sv_2mortal(*val); \
  	} \
  	else { \
  	  var = (HV *)sv_2mortal((SV *)newHV()); \
  	  hv_store(hv, #key, sizeof(#key)-1, newRV((SV *)var), 0) ; \
  	} \
  }


static int bw[4] = {
	[ 0 ] = 8,
	[ 1 ] = 7,
	[ 2 ] = 6,
	[ 3 ] = 5,
    };
static int co_t[4] = { 
	[ 0 ] = 0,	/* QPSK */
	[ 1 ] = 16,
	[ 2 ] = 64,
    };
static int hi[4] = {
	[ 0 ] = 0,
	[ 1 ] = 1,
	[ 2 ] = 2,
	[ 3 ] = 4,
    };
static int ra_t[8] = {
	[ 0 ] = 12,
	[ 1 ] = 23,
	[ 2 ] = 34,
	[ 3 ] = 56,
	[ 4 ] = 78,
    };
static int gu[4] = {
	[ 0 ] = 32,
	[ 1 ] = 16,
	[ 2 ] = 8,
	[ 3 ] = 4,
    };
static int tr[3] = {
	[ 0 ] = 2,
	[ 1 ] = 8,
	[ 2 ] = 4,
    };


/*---------------------------------------------------------------------------------------------------*/
static char *_to_string(char *str)
{
int i, j, len = strlen(str);
static char ret_str[8192] ;

   for (i=0, j=0; i < len; i++)
   {
	   ret_str[j++] = str[i] ;

	   /* terminate */
	   ret_str[j] = 0 ;
   }
   return ret_str ;
}

static int DVBT_DEBUG = 0 ;


MODULE = Linux::DVB::DVBT		PACKAGE = Linux::DVB::DVBT

PROTOTYPES: ENABLE

 # /*---------------------------------------------------------------------------------------------------*/

SV *
dvb_device()
	INIT:
  AV * results;

	struct devinfo *entry ;
	struct list_head *info ;
	struct list_head *item, *safe;

  results = (AV *)sv_2mortal((SV *)newAV());

	CODE:

  /* get info */
  info = dvb_probe(0) ;

  /* TODO: return the device names too */

  /* Create Perl data */
  list_for_each(item, info)
  {
  HV * rh;
  HV * ch;
  int flags ;

		entry = list_entry(item, struct devinfo, next);

		/* Convert structure fields into hash elements */
		rh = (HV *)sv_2mortal((SV *)newHV());

      /*  char  device[32];
          int adapter_num ;
          int frontend_num ;
          char  name[32];
          char  bus[32];
          int   flags;
		*/

		HVS_S(rh, entry, device) ;
		HVS_S(rh, entry, name) ;
		HVS_I(rh, entry, adapter_num) ;
		HVS_I(rh, entry, frontend_num) ;
		HVS_I(rh, entry, flags) ;
		
		flags = entry->flags ;
		
		// Convert flags into capabilities HASH
		//	typedef enum fe_caps {
		//		FE_IS_STUPID			= 0,
		//		FE_CAN_INVERSION_AUTO		= 0x1,
		//		FE_CAN_FEC_1_2			= 0x2,
		//		FE_CAN_FEC_2_3			= 0x4,
		//		FE_CAN_FEC_3_4			= 0x8,
		//		FE_CAN_FEC_4_5			= 0x10,
		//		FE_CAN_FEC_5_6			= 0x20,
		//		FE_CAN_FEC_6_7			= 0x40,
		//		FE_CAN_FEC_7_8			= 0x80,
		//		FE_CAN_FEC_8_9			= 0x100,
		//		FE_CAN_FEC_AUTO			= 0x200,
		//		FE_CAN_QPSK			= 0x400,
		//		FE_CAN_QAM_16			= 0x800,
		//		FE_CAN_QAM_32			= 0x1000,
		//		FE_CAN_QAM_64			= 0x2000,
		//		FE_CAN_QAM_128			= 0x4000,
		//		FE_CAN_QAM_256			= 0x8000,
		//		FE_CAN_QAM_AUTO			= 0x10000,
		//		FE_CAN_TRANSMISSION_MODE_AUTO	= 0x20000,
		//		FE_CAN_BANDWIDTH_AUTO		= 0x40000,
		//		FE_CAN_GUARD_INTERVAL_AUTO	= 0x80000,
		//		FE_CAN_HIERARCHY_AUTO		= 0x100000,
		//		FE_CAN_8VSB			= 0x200000,
		//		FE_CAN_16VSB			= 0x400000,
		//		FE_NEEDS_BENDING		= 0x20000000, // not supported anymore, don't use (frontend requires frequency bending)
		//		FE_CAN_RECOVER			= 0x40000000, // frontend can recover from a cable unplug automatically
		//		FE_CAN_MUTE_TS			= 0x80000000  // frontend can stop spurious TS data output
		//	} fe_caps_t;
		
		ch = (HV *)sv_2mortal((SV *)newHV());
		HVS_BIT(ch, flags, FE_CAN_INVERSION_AUTO) ;
		
		HVS_BIT(ch, flags, FE_CAN_FEC_1_2) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_2_3) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_3_4) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_4_5) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_5_6) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_6_7) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_7_8) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_AUTO) ;
		
		HVS_BIT(ch, flags, FE_CAN_QPSK) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_16) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_32) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_64) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_128) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_256) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_AUTO) ;
		
		HVS_BIT(ch, flags, FE_CAN_TRANSMISSION_MODE_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_BANDWIDTH_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_GUARD_INTERVAL_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_HIERARCHY_AUTO) ;
		
		HVS_BIT(ch, flags, FE_CAN_8VSB) ;
		HVS_BIT(ch, flags, FE_CAN_16VSB) ;
		
		HVS_BIT(ch, flags, FE_CAN_RECOVER) ;
		HVS_BIT(ch, flags, FE_CAN_MUTE_TS) ;

		HVS(ch, FE_IS_STUPID, newSViv(flags==0 ? 1 : 0)) ;

		HVS(rh, capabilities, newRV((SV *)ch)) ;
		
		av_push(results, newRV((SV *)rh));

  }


	/* Free up results */
  /* TODO: Provide C call to do this */
  list_for_each_safe(item,safe,info)
  {
		entry = list_entry(item, struct devinfo, next);
		list_del(&entry->next);
		free(entry);
  };


  RETVAL = newRV((SV *)results);
	OUTPUT:
  RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

SV *
dvb_device_names(DVB *dvb)
	INIT:
        HV * results;

	CODE:
		results = (HV *)sv_2mortal((SV *)newHV());

		/* get device names from dvb struct */
		HVS(results, fe_name, newSVpv(dvb->frontend, 0)) ;
		HVS(results, demux_name, newSVpv(dvb->demux, 0)) ;
		HVS(results, dvr_name, newSVpv(dvb->dvr, 0)) ;

	    RETVAL = newRV((SV *)results);
	  OUTPUT:
	    RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

DVB *
dvb_init(char *adapter, int frontend)
	CODE:
	 RETVAL = dvb_init(adapter, frontend) ;
	OUTPUT:
	 RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

DVB *
dvb_init_nr(int adapter_num, int frontend_num)
	CODE:
	 RETVAL = dvb_init_nr(adapter_num, frontend_num) ;
	OUTPUT:
	 RETVAL

 # /*---------------------------------------------------------------------------------------------------*/

void
dvb_fini(DVB *dvb);
	CODE:
	 dvb_fini(dvb) ;


 # /*---------------------------------------------------------------------------------------------------*/

void
dvb_set_debug(int debug);
	CODE:
	 dvb_debug = debug ;
	 DVBT_DEBUG = debug ;


 # /*---------------------------------------------------------------------------------------------------*/

void
dvb_clear_epg();
	CODE:
	 clear_epg() ;


 # /*---------------------------------------------------------------------------------------------------*/
 # /* Use the specified parameters (or AUTO) to tune the frontend */
 
int
dvb_tune (DVB *dvb, HV *parameters)
    INIT:
		SV **val;

		int frequency=0;

		/* We hope that any unset params will cope just using the AUTO option */
		int inversion=0;
		int bandwidth=TUNING_AUTO;
		int code_rate_high=TUNING_AUTO;
		int code_rate_low=TUNING_AUTO;
		int modulation=TUNING_AUTO;
		int transmission=TUNING_AUTO;
		int guard_interval=TUNING_AUTO;
		int hierarchy=TUNING_AUTO;

		int timeout=DEFAULT_TIMEOUT;

	CODE:

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, " == DVBT.xs::dvb_tune() ================\n") ;
 }

		/* Read all those HASH values that are actually set into discrete variables */
		HVF_I(parameters, frequency) ;
		HVF_I(parameters, inversion) ;
		HVF_I(parameters, bandwidth) ;
		HVF_I(parameters, code_rate_high) ;
		HVF_I(parameters, code_rate_low) ;
		HVF_I(parameters, modulation) ;
		HVF_I(parameters, transmission) ;
		HVF_I(parameters, guard_interval) ;
		HVF_I(parameters, hierarchy) ;
		HVF_I(parameters, timeout) ;

		if (frequency <= 0)
	          croak ("Linux::DVB::DVBT::dvb_tune requires a valid frequency");

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@f DVBT.xs::dvb_tune() : tuning freq=%d Hz, inv=(%d) "
		"bandwidth=(%d) code_rate=(%d - %d) constellation=(%d) "
		"transmission=(%d) guard=(%d) hierarchy=(%d)\n",
		frequency,
		inversion,
		bandwidth,
		code_rate_high,
		code_rate_low,
		modulation,
		transmission,
		guard_interval,
		hierarchy
	) ;
 }

		// set tuning
		RETVAL = dvb_tune(dvb,
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

	OUTPUT:
        RETVAL


 # /*---------------------------------------------------------------------------------------------------*/
 # /* Same as dvb_tune() but ensures that the frequency tuned to is added to the scan list */
int
dvb_scan_tune (DVB *dvb, HV *parameters)
    INIT:
		SV **val;

		int frequency=0;

		/* We hope that any unset params will cope just using the AUTO option */
		int inversion=0;
		int bandwidth=TUNING_AUTO;
		int code_rate_high=TUNING_AUTO;
		int code_rate_low=TUNING_AUTO;
		int modulation=TUNING_AUTO;
		int transmission=TUNING_AUTO;
		int guard_interval=TUNING_AUTO;
		int hierarchy=TUNING_AUTO;

		int timeout=DEFAULT_TIMEOUT;

	CODE:

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, " == DVBT.xs::dvb_scan_tune() ================\n") ;
 }

		/* Read all those HASH values that are actually set into discrete variables */
		HVF_I(parameters, frequency) ;
		HVF_I(parameters, inversion) ;
		HVF_I(parameters, bandwidth) ;
		HVF_I(parameters, code_rate_high) ;
		HVF_I(parameters, code_rate_low) ;
		HVF_I(parameters, modulation) ;
		HVF_I(parameters, transmission) ;
		HVF_I(parameters, guard_interval) ;
		HVF_I(parameters, hierarchy) ;
		HVF_I(parameters, timeout) ;

		if (frequency <= 0)
	          croak ("Linux::DVB::DVBT::dvb_tune requires a valid frequency");

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@f DVBT.xs::dvb_tune() : tuning freq=%d Hz, inv=(%d) "
		"bandwidth=(%d) code_rate=(%d - %d) constellation=(%d) "
		"transmission=(%d) guard=(%d) hierarchy=(%d)\n",
		frequency,
		inversion,
		bandwidth,
		code_rate_high,
		code_rate_low,
		modulation,
		transmission,
		guard_interval,
		hierarchy
	) ;
 }

		// set tuning
		RETVAL = dvb_scan_tune(dvb,
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

	OUTPUT:
        RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Remove the demux filter (specified via the file handle) */
int
dvb_del_demux (DVB *dvb, int fd)

	CODE:
		if (fd > 0)
		{
			// delete demux filter
			RETVAL = dvb_demux_remove_filter(dvb, fd) ;
		}
		else
		{
			RETVAL = -1 ;
		}
		
	OUTPUT:
       RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Set the DEMUX to add a new stream specified by it's pid. Returns file handle or negative if fail */
int
dvb_add_demux (DVB *dvb, unsigned int pid)

	CODE:
		// set demux
		RETVAL = dvb_demux_add_filter(dvb, pid) ;

	OUTPUT:
       RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Stream the raw TS data to a file (assumes frontend & demux are already set up  */
int
dvb_record (DVB *dvb, char *filename, int sec)
	CODE:
		if (sec <= 0)
	          croak ("Linux::DVB::DVBT::dvb_record requires a valid record length in seconds");


		// open dvr first
		RETVAL = dvb_dvr_open(dvb) ;

        // save stream
		if (RETVAL == 0)
		{
			RETVAL = write_stream(dvb, filename, sec) ;

			// close dvr
			dvb_dvr_release(dvb) ;
		}


	OUTPUT:
      RETVAL


 # /*---------------------------------------------------------------------------------------------------*/
 # /* Set up for scanning */

void
dvb_scan_new(DVB *dvb, int verbose)
	CODE:
		// init the freq list
		clear_freqlist() ;

 # /*---------------------------------------------------------------------------------------------------*/
 # /* Set up for scanning */

void
dvb_scan_init(DVB *dvb, int verbose)
	CODE:
	 	dvb_scan_init(dvb, verbose) ;

 # /*---------------------------------------------------------------------------------------------------*/
 # /* Clear up after scanning */

void
dvb_scan_end(DVB *dvb, int verbose)
	CODE:
 		/* Free up results */
		dvb_scan_end(dvb, verbose) ;

 # /*---------------------------------------------------------------------------------------------------*/
 # /* Scan all frequencies starting from whatever the current tuning is */
SV *
dvb_scan(DVB *dvb, int verbose)

  INIT:
    HV * results;

    AV * streams ;
    HV * freqs ;
    AV * programs ;

    char key[256] ;
    char key2[256] ;

    struct dvbmon *dm ;
	struct list_head *item, *safe, *pitem, *fitem ;
	struct psi_program *program ;
	struct psi_stream *stream;
	struct prog_info *pinfo ;
    struct freqitem   *freqi;
    struct freq_info  *finfo;

    results = (HV *)sv_2mortal((SV *)newHV());

    streams = (AV *)sv_2mortal((SV *)newAV());
    programs = (AV *)sv_2mortal((SV *)newAV());
    freqs = (HV *)sv_2mortal((SV *)newHV());

  CODE:
  	/* get info */
    dm = dvb_scan_freqs(dvb, verbose) ;

  	/** Create Perl data **/
	HVS(results, ts, newRV((SV *)streams)) ;
	HVS(results, pr, newRV((SV *)programs)) ;
	HVS(results, freqs, newRV((SV *)freqs)) ;

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "\n\n == DVBT.xs::dvb_scan() ================\n") ;
	
 }

    /* Store frequency info */
    list_for_each(item,&freq_list) 
    {
		HV * fh;
    
		freqi = list_entry(item, struct freqitem, next);
		
 if (DVBT_DEBUG >= 10)
 {
		fprintf(stderr, "#@f FREQ: %d Hz seen=%d tuned=%d (Strength=%d)\n",
			freqi->frequency,
			freqi->flags.seen,
			freqi->flags.tuned,
			freqi->strength
		) ;
 }
		/* Convert structure fields into hash elements */
		fh = (HV *)sv_2mortal((SV *)newHV());

		HVS_I(fh, freqi, strength) ;
		HVS(fh, seen, newSViv(freqi->flags.seen)) ;
		HVS(fh, tuned, newSViv(freqi->flags.tuned)) ;

		// Convert frontend params into VDR values
		HVS_INT(fh, inversion, freqi->params.inversion) ;
		HVS_INT(fh, bandwidth, bw[ freqi->params.u.ofdm.bandwidth ] );
		HVS_INT(fh, code_rate_high, ra_t[ freqi->params.u.ofdm.code_rate_HP ] );
		HVS_INT(fh, code_rate_low, ra_t[ freqi->params.u.ofdm.code_rate_LP ] );
		HVS_INT(fh, modulation, co_t[ freqi->params.u.ofdm.constellation ] );
		HVS_INT(fh, transmission, tr[ freqi->params.u.ofdm.transmission_mode ] );
		HVS_INT(fh, guard_interval, gu[ freqi->params.u.ofdm.guard_interval ] );
		HVS_INT(fh, hierarchy, hi[ freqi->params.u.ofdm.hierarchy_information ] );

		sprintf(key, "%d", freqi->frequency) ;
		hv_store(freqs, key, strlen(key),  newRV((SV *)fh), 0) ;
    }



    /* Store stream info */
	list_for_each(item,&dm->info->streams)
	{
		HV * rh;
		HV * tsidh;
		int frequency ;
		
		stream = list_entry(item, struct psi_stream, next);

			// round up frequency to nearest kHz
			// HVS_I(rh, stream, frequency) ;
			frequency = (int)(  ((float)stream->frequency / 1000.0) + 0.5 ) * 1000 ;  

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@f  stream: TSID %d freq = %d Hz [%d Hz] : tuned=%d updated=%d\n",
		stream->tsid,
		stream->frequency,
		frequency,
		stream->tuned,
		stream->updated
	) ;
 }
 

			/*
			//    	  int                  tsid;
			//
			//        // network //
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
			*/
	
			/* Convert structure fields into hash elements */
			rh = (HV *)sv_2mortal((SV *)newHV());
			tsidh = (HV *)sv_2mortal((SV *)newHV());

			HVS_INT(rh, frequency, frequency) ;
	
			HVS_I(rh, stream, tsid) ;
			HVS_I(rh, stream, netid) ;
			HVS_S(rh, stream, bandwidth) ;
			HVSN_S(rh, stream, code_rate_hp, 	code_rate_high) ;
			HVSN_S(rh, stream, code_rate_lp, 	code_rate_low) ;
			HVSN_S(rh, stream, constellation, 	modulation) ;
			HVSN_S(rh, stream, guard, 			guard_interval) ;
			HVS_S(rh, stream, hierarchy) ;
			HVS_S(rh, stream, net) ;
			HVS_S(rh, stream, transmission) ;
	
			/* Process the program lcns attached to this stream 
			
			'lcn' => {
			
				$tsid => {
				
					$pnr => {
						'service_type' => xx,
						'visible' => yy,
						'lcn' => zz,
					}
				}
			}
			*/
			list_for_each(pitem,&stream->prog_info_list)
			{
				/* Convert structure fields into hash elements */
				HV * pnrh = (HV *)sv_2mortal((SV *)newHV());
	
				pinfo = list_entry(pitem, struct prog_info, next);

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@p  + LCN: %d (pnr %d) type=%d visible=%d\n",
		pinfo->lcn,
		pinfo->service_id,
		pinfo->service_type,
		pinfo->visible
	) ;
 }
	
				if (pinfo->lcn > 0)
				{
					/*			
					int 				 service_id ; # same as pnr
					int 				 service_type ;
					int					 visible ;
					int					 lcn ;
					*/
					HVS_I(pnrh, pinfo, service_type) ;
					HVS_I(pnrh, pinfo, visible) ;
					HVS_I(pnrh, pinfo, lcn) ;
					
					sprintf(key2, "%d", pinfo->service_id) ;
					hv_store(tsidh, key2, strlen(key2),  newRV((SV *)pnrh), 0) ;
				}
			}
			HVS(rh, lcn, newRV((SV *)tsidh)) ;

			av_push(streams, newRV((SV *)rh));
			
	}

	/* store program info */
	list_for_each(item,&dm->info->programs)
	{
		program = list_entry(item, struct psi_program, next);

	    if (DVBT_DEBUG >= 15)
	    {
	    	print_program(program) ;
	    }
	
		/*
		//         int                  tsid;
		//         int                  pnr;
		//         int                  version;
		//         int                  running;
		//         int                  ca;
		//
		//         // program data //
		//         int                  type;
		//         int                  p_pid;             // program
		//         int                  v_pid;             // video
		//         int                  a_pid;             // audio
		//         int                  t_pid;             // teletext
		//         char                 audio[PSI_STR_MAX];
		//         char                 net[PSI_STR_MAX];
		//         char                 name[PSI_STR_MAX];
		//
		//         // status info //
		//         int                  updated;
		//         int                  seen;
		*/

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@p PROG %d-%d: %s\n",
		program->tsid,
		program->pnr,
		program->name
	) ;
 }

		/* Only bother saving this if the same is set AND type > 0*/
		if ((strlen(program->name) > 0) && (program->type > 0))
		{
		HV * rh;
		AV * freq_array;
		int frequency ;
		
			/* Convert structure fields into hash elements */
			rh = (HV *)sv_2mortal((SV *)newHV());

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@p + PID %d  Video=%d Audio=%d Teletext=%d (type=%d)\n",
		program->p_pid,
		program->v_pid,
		program->a_pid,
		program->t_pid,
		program->type
	) ;
 }

			HVS_I(rh, program, tsid) ;
			HVS_I(rh, program, pnr) ;
			HVS_I(rh, program, ca) ;
			HVS_I(rh, program, type) ;
			HVSN_I(rh, program, v_pid, 	video) ;
			HVSN_I(rh, program, a_pid,	audio) ;
			HVSN_I(rh, program, t_pid,	teletext) ;
			HVSN_I(rh, program, s_pid,	subtitle) ;
			HVSN_S(rh, program, audio,	audio_details) ;
			HVS_S(rh, program, net) ;
			HVS_S(rh, program, name) ;

			// add frequencies
			freq_array = (AV *)sv_2mortal((SV *)newAV());
		    list_for_each(fitem,&program->tuned_freq_list) {
		        finfo = list_entry(fitem, struct freq_info, next);

				// round up frequency to nearest kHz
				frequency = (int)(  ((float)(finfo->frequency) / 1000.0) + 0.5 ) * 1000 ;  
		        
 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "#@f + + freq = %d Hz [%d Hz]\n",
		finfo->frequency, frequency
	) ;
 }

		        AVS_I(freq_array, frequency) ;
		    }
			HVS(rh, freqs, newRV((SV *)freq_array)) ;
			
			// save entry in list
			av_push(programs, newRV((SV *)rh));
			
		}
	}

 if (DVBT_DEBUG >= 10)
 {
	fprintf(stderr, "\n\n == DVBT.xs::dvb_scan() - END =============\n") ;
 }


    RETVAL = newRV((SV *)results);
  OUTPUT:
    RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Scan all streams to gather all EPG information */
SV *
dvb_epg(DVB *dvb, int verbose, int alive, int section)

 INIT:
   AV * results;

	struct list_head *epg_list ;
	struct list_head *item, *safe;
    struct epgitem   *epg;
    struct epgitem   dummy_epg;

   results = (AV *)sv_2mortal((SV *)newAV());

 CODE:

	/*
	   // NOTE: Mask allows for multiple sections
	   // e.g. 0x50, 0xf0 means "read sections 0x50 - 0x5f"

	   //
		//    0x4E event_information_section - actual_transport_stream, present/following
		//    0x4F event_information_section - other_transport_stream, present/following
		//    0x50 to 0x5F event_information_section - actual_transport_stream, schedule
		//    0x60 to 0x6F event_information_section - other_transport_stream, schedule
	   //
	   // 0x50 - 0x6f => 01010000 - 01101111
	*/
	if (section)
	{
		epg_list = get_eit(/* struct dvb_state *dvb */ dvb,
	   		/* int section */section, /* int mask */0xff,
	   		/* int verbose */ verbose, /* int alive */ alive) ;
	}
	else
	{
		get_eit(/* struct dvb_state *dvb */ dvb,
			/* int section */0x50, /* int mask */0xf0,
			/* int verbose */ verbose, /* int alive */ alive) ;

		epg_list = get_eit(/* struct dvb_state *dvb */ dvb,
			/* int section */0x60, /* int mask */0xf0,
			/* int verbose */ verbose, /* int alive */ alive) ;
	}

    if (epg_list)
    {
		/* Create Perl data */
		list_for_each(item, epg_list)
		{
		HV * rh;

			epg = list_entry(item, struct epgitem, next);

			/* Convert structure fields into hash elements */
			rh = (HV *)sv_2mortal((SV *)newHV());

			HVS_I(rh, epg, id) ;
			HVS_I(rh, epg, tsid) ;
			HVS_I(rh, epg, pnr) ;
			HVS_I(rh, epg, start) ;
			HVS_I(rh, epg, stop) ;
			HVS_I(rh, epg, flags) ;

			if (epg->lang[0])
			{
				HVS_STRING(rh, epg, lang);
			}
			if (epg->name[0])
			{
				HVS_STRING(rh, epg, name);
			}
			if (epg->stext[0])
			{
				HVS_STRING(rh, epg, stext);
			}
			if (epg->etext)
			{
				HVS_STRING(rh, epg, etext);
			}
			if (epg->playing)
			{
				HVS_I(rh, epg, playing) ;
			}
			if (epg->cat[0])
			{
				hv_store(rh, "genre", sizeof("genre")-1, newSVpv(_to_string(epg->cat[0]), 0), 0) ;
			}
			if (epg->tva_prog[0])
			{
				HVS_STRING(rh, epg, tva_prog);
			}
			if (epg->tva_series[0])
			{
				HVS_STRING(rh, epg, tva_series);
			}

			av_push(results, newRV((SV *)rh));
	   }


   }

   RETVAL = newRV((SV *)results);
 OUTPUT:
   RETVAL

 # /*---------------------------------------------------------------------------------------------------*/
 # /* Get frontend signal stats */
SV *
dvb_signal_quality(DVB *dvb)

  INIT:
    HV * results;
	unsigned 		ber ;
	unsigned		snr ;
	unsigned		strength ;
	unsigned		uncorrected_blocks ;
	int ok ;

    results = (HV *)sv_2mortal((SV *)newHV());

  CODE:
  	/* get info */
    ok = dvb_signal_quality(dvb, &ber, &snr, &strength, &uncorrected_blocks) ; 

  	/** Create Perl data **/
	HVS(results, ber, newSViv((int)ber)) ;
	HVS(results, snr, newSViv((int)snr)) ;
	HVS(results, strength, newSViv((int)strength)) ;
	HVS(results, uncorrected_blocks, newSViv((int)uncorrected_blocks)) ;
	HVS(results, ok, newSViv(ok)) ;

    RETVAL = newRV((SV *)results);
  OUTPUT:
    RETVAL

 # /*---------------------------------------------------------------------------------------------------*/
 # /* Record a multiplex */
 #
 #	struct multiplex_file_struct {
 #		int								file;
 #		time_t 							start;
 #		time_t 							end;
 #	    unsigned int                    done;
 #	} ;
 #	
 #	struct multiplex_pid_struct {
 #	    struct multiplex_file_struct	 *file_info ;
 #	    unsigned int                     pid;
 #	} ;
 #

int
dvb_record_demux (DVB *dvb, SV *multiplex_aref)

  INIT:
	unsigned 		num_entries ;
	int				i ;
	SV				**item ;
	SV 				**val;
	HV				*href ;
	char			*str ;

    AV 				*pid_array;
	unsigned 		num_pids ;
	int				j ;
	SV				**piditem ;
	
	struct multiplex_file_struct	*file_info ;
	struct multiplex_pid_struct		*pid_list ;
	unsigned						pid_list_length ;
	unsigned						pid_index;
	
	time_t 		now, start, end;
	int			file ;
	int rc ;

  CODE:

	if ((!SvROK(multiplex_aref))
	|| (SvTYPE(SvRV(multiplex_aref)) != SVt_PVAV))
	{
	 	croak("Linux::DVB::DVBT::dvb_record_demux requires a valid array ref") ;
	}
 
    // av_len returns -1 for empty. Returns maximum index number otherwise
	num_entries = av_len( (AV *)SvRV(multiplex_aref) ) + 1 ;
	if (num_entries <= 0)
	{
	 	croak("Linux::DVB::DVBT::dvb_record_demux requires a list of multiplex hashes") ;
	}

	// count number of entries (and check structure)
	pid_list_length = 0 ;

	for (i=0; i <= num_entries ; i++) 
	{ 
		if ((item = av_fetch((AV *)SvRV(multiplex_aref), i, 0)) && SvOK (*item)) 
		{
  			if ( SvTYPE(SvRV(*item)) != SVt_PVHV )
  			{
 			 	croak("Linux::DVB::DVBT::dvb_record_demux requires a list of multiplex hashes") ;
 			}
 			href = (HV *)SvRV(*item) ;

 			// get pids
 			val = HVF(href, pids) ;
 			pid_array = (AV *) SvRV (*val); 
 			num_pids = av_len(pid_array) + 1 ;

			pid_list_length += num_pids ;
		}
	}

	// create arrays
	now = time(NULL);
 	pid_list = (struct multiplex_pid_struct *)safemalloc( sizeof(struct multiplex_pid_struct) * pid_list_length); 
 	file_info = (struct multiplex_file_struct *)safemalloc( sizeof(struct multiplex_file_struct) * num_entries );

	for (i=0, pid_index=0; i <= num_entries ; i++) 
	{ 
		if ((item = av_fetch((AV *)SvRV(multiplex_aref), i, 0)) && SvOK (*item)) 
		{
 			href = (HV *)SvRV(*item) ;

 			val = HVF(href, destfile) ;
 			str = (char *)SvPV(*val, SvLEN(*val)) ;
			file = open(str, O_WRONLY | O_TRUNC | O_CREAT | O_LARGEFILE, 0666);
		    if (-1 == file) {
		    
				fprintf(stderr,"open %s: %s\n",str,strerror(errno));
				croak("Linux::DVB::DVBT::dvb_record_demux failed to write to file") ;
		    }
			
			// create file info struct
		 	file_info[i].file = file ;

 			val = HVF(href, offset) ;
		 	file_info[i].start = now + SvIV (*val) ;

 			val = HVF(href, duration) ;
		 	file_info[i].end = file_info[i].start + SvIV (*val) ;


 			// get pids
 			val = HVF(href, pids) ;
 			pid_array = (AV *) SvRV (*val); 
 			num_pids = av_len(pid_array) + 1 ;
 			
 			for (j=0; j < num_pids ; j++, ++pid_index) 
 			{ 
 				if ((piditem = av_fetch(pid_array, j, 0)) && SvOK (*piditem)) 
 				{
 					pid_list[pid_index].file_info = &file_info[i] ;
 					pid_list[pid_index].pid  = SvIV (*piditem) ;
 					pid_list[pid_index].done = 0 ;
 					pid_list[pid_index].pkts = 0 ;
 				}
 			}			

		}
	}

 	// open dvr first
 	RETVAL = dvb_dvr_open(dvb) ;
 
     // save stream
 	if (RETVAL == 0)
 	{
 		RETVAL = write_stream_demux(dvb, pid_list, pid_index) ;
 
 		// close dvr
 		dvb_dvr_release(dvb) ;
 	}

 	// free up
 	for (i=0; i < num_entries ; i++) 
 	{ 
 		if (file_info[i].file > 0)
 		{
 			close(file_info[i].file) ;
 		}
 	}
 	safefree(pid_list) ;
 	safefree(file_info) ;
	

  OUTPUT:
    RETVAL




 # /*---------------------------------------------------------------------------------------------------*/


