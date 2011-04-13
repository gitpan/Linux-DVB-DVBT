/*
 * parse_desc.c
 *
 *  Created on: 2 Apr 2011
 *      Author: sdprice1
 */


// VERSION = 1.00

/*=============================================================================================*/
// USES
/*=============================================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>

#include "parse_desc.h"
#include "ts_bits.h"

/*=============================================================================================*/
// CONSTANTS
/*=============================================================================================*/

/*=============================================================================================*/
// MACROS
/*=============================================================================================*/

/*=============================================================================================*/
// FUNCTIONS
/*=============================================================================================*/

/* ----------------------------------------------------------------------- */
//
//descriptor(){
//descriptor_tag 8 uimsbf
//descriptor_length 8 uimsbf
//...
//}

unsigned parse_desc(struct TS_bits *bits)
{
printf("[buff: 0x%02x 0x%02x 0x%02x 0x%02x ... :: start: %d :: len %d]\n",
		bits->buff_ptr[0],
		bits->buff_ptr[1],
		bits->buff_ptr[2],
		bits->buff_ptr[3],
		bits->start_bit,
		bits->buff_len
		);
	// common
	unsigned tag = bits_get(bits, 8) ;
	unsigned len = bits_get(bits, 8) ;

printf("    Descriptor 0x%02x (len %d)\n", tag, len);
bits_skip(bits, len*8) ;

	return len+2 ;
}
