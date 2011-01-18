/*---------------------------------------------------------------------------------------------------*/
#include <linux/dvb/frontend.h>
#include <linux/dvb/dmx.h>

#include "list.h"

#include "dvb_struct.h"
#include "dvb_lib.h"
#include "ts.h"

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

/* Specify the structure field name and HASH key name separately */
#define HVSN_S(h, sp, name, key)		if (sp->name)      hv_store(h, #key, sizeof(#key)-1, newSVpv(sp->name, 0), 0)
#define HVSN_I(h, sp, name, key)		if (sp->name >= 0) hv_store(h, #key, sizeof(#key)-1, newSViv(sp->name), 0)

/* Convert string before storing in hash */
#define HVS_STRING(h, sp, name)		hv_store(h, #name, sizeof(#name)-1, newSVpv(_to_string(sp->name), 0), 0)

/* non-struct member versions */
#define HVS_INT(h, name, i)		hv_store(h, #name, sizeof(#name)-1, newSViv(i), 0)
#define HVS_STR(h, name, s)		hv_store(h, #name, sizeof(#name)-1, newSVpv(s, 0), 0)


/** HASH read macros **/
#define HVF_I(hv,var)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      var = SvIV (*val); \
  	  if (DVBT_DEBUG) fprintf(stderr, " set %s = %d\n", #var, var); \
  	} \
  }

#define HVF_SV(hv,var)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      var = SvSV (*val); \
  	} \
  }

#define HVF_IV(hv,var,ival)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      ival = SvIV (*val); \
  	} \
  }

#define HVF_SVV(hv,var,sval)                                 \
  if ( (val = hv_fetch (hv, #var, sizeof (#var) - 1, 0)) ) { \
  	if ( val != NULL ) { \
      sval = (*val); \
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


/*---------------------------------------------------------------------------------------------------*/

static int DVBT_DEBUG = 0 ;

static int fe_vdr_bandwidth[] = {
	[ BANDWIDTH_AUTO  ] = VDR_MAX,
	[ BANDWIDTH_8_MHZ ] = 8,
	[ BANDWIDTH_7_MHZ ] = 7,
	[ BANDWIDTH_6_MHZ ] = 6,
};

static int fe_vdr_rates[] = {
	[ FEC_AUTO ] = VDR_MAX,
	[ FEC_1_2  ] = 12,
	[ FEC_2_3  ] = 23,
	[ FEC_3_4  ] = 34,
	[ FEC_4_5  ] = 45,
	[ FEC_5_6  ] = 56,
	[ FEC_6_7  ] = 67,
	[ FEC_7_8  ] = 78,
	[ FEC_8_9  ] = 89,
};

static int fe_vdr_modulation[] = {
	[ QAM_AUTO ] = VDR_MAX,
	[ QPSK     ] = 0,
	[ QAM_16   ] = 16,
	[ QAM_32   ] = 32,
	[ QAM_64   ] = 64,
	[ QAM_128  ] = 128,
	[ QAM_256  ] = 256,
};

static int fe_vdr_transmission[] = {
	[ TRANSMISSION_MODE_AUTO ] = VDR_MAX,
	[ TRANSMISSION_MODE_2K   ] = 2,
	[ TRANSMISSION_MODE_8K   ] = 8,
};

static int fe_vdr_guard[] = {
	[ GUARD_INTERVAL_AUTO ] = VDR_MAX,
	[ GUARD_INTERVAL_1_4  ] = 4,
	[ GUARD_INTERVAL_1_8  ] = 8,
	[ GUARD_INTERVAL_1_16 ] = 16,
	[ GUARD_INTERVAL_1_32 ] = 32,
};

static int fe_vdr_hierarchy[] = {
	[ HIERARCHY_AUTO ] = VDR_MAX,
	[ HIERARCHY_NONE ] = 0,
	[ HIERARCHY_1 ]    = 1,
	[ HIERARCHY_2 ]    = 2,
	[ HIERARCHY_4 ]    = 4,
};

static int fe_vdr_inversion[] = {
	[ INVERSION_OFF  ] = 0,
	[ INVERSION_ON   ] = 1,
	[ INVERSION_AUTO   ] = VDR_MAX,
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

/*---------------------------------------------------------------------------------------------------*/
// MACROS for DVBT-advert

#define HVS_INT_SETTING(h, name, i, prefix)		HVS_INT(h, name, i)
#define HVS_INT_RESULT(h, name, i)				HVS_INT(h, name, i)


// Store result
#define HVS_FRAME_RESULT(h, NAME, IDX)		HVS_INT(h, NAME, user_data->results_array[IDX].frame_results.NAME)
#define HVS_LOGO_RESULT(h, NAME, IDX)		HVS_INT(h, NAME, user_data->results_array[IDX].logo_results.NAME)
#define HVS_AUDIO_RESULT(h, NAME, IDX)		HVS_INT(h, NAME, user_data->results_array[IDX].audio_results.NAME)
#define HVS_RESULT_START
#define HVS_RESULT_END


