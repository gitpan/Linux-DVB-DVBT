#ifndef DVB_LIB
#define DVB_LIB

#include <linux/dvb/frontend.h>
#include <linux/dvb/dmx.h>

#include "dvb_struct.h"
#include "dvb_tune.h"
#include "dvb_epg.h"
#include "dvb_scan.h"
#include "dvb_stream.h"

#include "list.h"


/* ----------------------------------------------------------------------- */
// MACROS
/* ----------------------------------------------------------------------- */

#define DVB_FN_START(name)	\
char *_name="name" ; \
if (dvb_debug>1) _fn_start(_name) ;

#define DVB_FN_END(err)	\
if (dvb_debug>1) _fn_end(_name, err) ;



/* ----------------------------------------------------------------------- */
// CONSTANTS
/* ----------------------------------------------------------------------- */

#define MAX_ADAPTERS	4
#define MAX_FRONTENDS	4

/* ----------------------------------------------------------------------- */
// FUNCTIONS
/* ----------------------------------------------------------------------- */

int setNonblocking(int fd) ;

/* ----------------------------------------------------------------------- */
// PERL INTERFACE
/* ----------------------------------------------------------------------- */

struct list_head* dvb_probe(int debug) ;

#endif
