/*---------------------------------------------------------------------------------------------------*/
#include <linux/dvb/frontend.h>
#include <linux/dvb/dmx.h>

#include "dvb_struct.h"
#include "dvb_lib.h"
#include "ts.h"

#define DEFAULT_TIMEOUT		900

// If large file support is not included, then make the value do nothing
#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

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




