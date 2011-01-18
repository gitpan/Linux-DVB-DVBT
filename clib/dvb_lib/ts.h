/*
 * ts.h
 *
 *  Created on: 29 Apr 2010
 *      Author: sdprice1
 */

#ifndef TS_H_
#define TS_H_

#include <inttypes.h>
#include "list.h"
#include "dvb_error.h"

/*=============================================================================================*/
// CONSTANTS
/*=============================================================================================*/

#define NULL_PID		0x1fff
#define MAX_PID			NULL_PID
#define ALL_PID			(MAX_PID+1)

// ISO 13818-1
#define SYNC_BYTE			0x47
#define TS_PACKET_LEN		188
#define MAX_SECTION_LEN 	1021
#define TS_FREQ				90000


#define FPS					25

// create a buffer that is a number of packets long
// (this is approx 4k)
#define BUFFSIZE		(22 * TS_PACKET_LEN)


// If large file support is not included, then make the value do nothing
#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

#ifndef O_BINARY
#define O_BINARY	0
#endif


// clear memory
#define CLEAR_MEM(mem)	memset(mem, 0, sizeof(*mem))


// PTS, timing etc
#define UNSET_TS			((int64_t)-1)
#define FPS					25
#define VIDEO_PTS_DELTA		(TS_FREQ / FPS)



#endif /* TS_H_ */
