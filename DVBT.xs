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

#define DVBT_VERSION		"1.005"
#define DEFAULT_TIMEOUT		900

/*---------------------------------------------------------------------------------------------------*/

/** HASH store macros **/

/* Use 'name' as structure field name AND HASH key name */
#define HVS(h, name, sv)		hv_store(h, #name, sizeof(#name)-1, sv, 0)
#define HVS_S(h, sp, name)		if (sp->name)      hv_store(h, #name, sizeof(#name)-1, newSVpv(sp->name, 0), 0)
#define HVS_I(h, sp, name)		if (sp->name >= 0) hv_store(h, #name, sizeof(#name)-1, newSViv(sp->name), 0)

/* Specify the structure field name and HASH key name separately */
#define HVSN_S(h, sp, name, key)		if (sp->name)      hv_store(h, #key, sizeof(#key)-1, newSVpv(sp->name, 0), 0)
#define HVSN_I(h, sp, name, key)		if (sp->name >= 0) hv_store(h, #key, sizeof(#key)-1, newSViv(sp->name), 0)

/* Convert string before storing in hash */
#define HVS_STRING(h, sp, name)		hv_store(h, #name, sizeof(#name)-1, newSVpv(_to_string(sp->name), 0), 0)

/** HASH read macros **/
#define HVF_I(hv,var)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) )	\
    var = SvIV (*val);


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
		int inversion=INVERSION_AUTO;
		int bandwidth=BANDWIDTH_AUTO;
		int code_rate_high=FEC_AUTO;
		int code_rate_low=FEC_AUTO;
		int modulation=QAM_AUTO;
		int transmission=TRANSMISSION_MODE_AUTO;
		int guard_interval=GUARD_INTERVAL_AUTO;
		int hierarchy=HIERARCHY_AUTO;

		int timeout=DEFAULT_TIMEOUT;

	CODE:
		/* Read all those HASH values that are actually set */
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
 # /* Set the DEMUX to the specified streams */
int
dvb_set_demux (DVB *dvb, int vpid, int apid, int tpid, int timeout)

	CODE:
		if (!timeout) timeout = DEFAULT_TIMEOUT ;
		
		// Initialise the demux filter
		dvb_demux_filter_setup(dvb, vpid, apid) ;

		// set demux
		RETVAL = dvb_finish_tune(dvb, timeout) ;

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
 # /* Scan all frequencies based from whatever the current tuning is */
SV *
dvb_scan(DVB *dvb, int verbose)

  INIT:
    HV * results;
    HV * streams ;
    HV * lcns ;
    HV * programs ;

    char key[256] ;
    char key2[256] ;

    struct dvbmon *dm ;
	struct list_head *item, *safe, *pitem ;
	struct psi_program *program ;
	struct psi_stream *stream;
	struct prog_info *pinfo ;

    results = (HV *)sv_2mortal((SV *)newHV());
    streams = (HV *)sv_2mortal((SV *)newHV());
    lcns = (HV *)sv_2mortal((SV *)newHV());
    programs = (HV *)sv_2mortal((SV *)newHV());

  CODE:
  	/* get info */
    dm = dvb_scan_freqs(dvb, verbose) ;

  	/** Create Perl data **/
	HVS(results, ts, newRV((SV *)streams)) ;
	HVS(results, pr, newRV((SV *)programs)) ;
	HVS(results, lcn, newRV((SV *)lcns)) ;

    /* Store stream info */
	list_for_each(item,&dm->info->streams)
	{
		HV * rh;
		HV * tsidh ;
		
		stream = list_entry(item, struct psi_stream, next);

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

		HVS_S(rh, stream, bandwidth) ;
		HVSN_S(rh, stream, code_rate_hp, 	code_rate_high) ;
		HVSN_S(rh, stream, code_rate_lp, 	code_rate_low) ;
		HVSN_S(rh, stream, constellation, 	modulation) ;
		HVS_I(rh, stream, frequency) ;
		HVSN_S(rh, stream, guard, 			guard_interval) ;
		HVS_S(rh, stream, hierarchy) ;
		HVS_S(rh, stream, net) ;
		HVS_S(rh, stream, transmission) ;

		sprintf(key, "%d", stream->tsid) ;
		hv_store(streams, key, strlen(key),  newRV((SV *)rh), 0) ;
		
		/* Process the program lcns attached to this stream 
		
		'lcns' => {
		
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

			/*			
			int 				 service_id ;
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
		hv_store(lcns, key, strlen(key),  newRV((SV *)tsidh), 0) ;
	}

	/* store program info */
	list_for_each(item,&dm->info->programs)
	{
		HV * rh;
		program = list_entry(item, struct psi_program, next);

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

		/* Only bother saving this if the same is set */
		if (strlen(program->name))
		{
			/* Convert structure fields into hash elements */
			rh = (HV *)sv_2mortal((SV *)newHV());

			HVS_I(rh, program, tsid) ;
			HVS_I(rh, program, pnr) ;
			HVS_I(rh, program, ca) ;
			HVS_I(rh, program, type) ;
			HVSN_I(rh, program, v_pid, 	video) ;
			HVSN_I(rh, program, a_pid,	audio) ;
			HVSN_I(rh, program, t_pid,	teletext) ;
			HVSN_S(rh, program, audio,	audio_details) ;
			HVS_S(rh, program, net) ;
			HVS_S(rh, program, name) ;

			hv_store(programs, program->name, strlen(program->name),  newRV((SV *)rh), 0) ;
		}

	}


	/* Free up results */
    dvbmon_fini(dm) ;


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

			av_push(results, newRV((SV *)rh));
	   }


   }

   RETVAL = newRV((SV *)results);
 OUTPUT:
   RETVAL

 # /*---------------------------------------------------------------------------------------------------*/


