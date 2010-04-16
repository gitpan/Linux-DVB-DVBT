/*---------------------------------------------------------------------------------------------------*/
#include <linux/dvb/frontend.h>
#include <linux/dvb/dmx.h>

#include "list.h"

#include "../dvb_lib/dvb_struct.h"
#include "../dvb_lib/dvb_lib.h"

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


/*---------------------------------------------------------------------------------------------------*/

static int DVBT_DEBUG = 0 ;


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


