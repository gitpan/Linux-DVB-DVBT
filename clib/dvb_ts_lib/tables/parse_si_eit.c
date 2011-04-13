/*
 * parse_si_eit.c
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

#include "parse_si_eit.h"

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
//event_information_section(){
//	table_id	8	uimsbf
//	section_syntax_indicator	1	bslbf
//	reserved_future_use	1	bslbf
//	reserved	2	bslbf
//	section_length	12	uimsbf
//
//	service_id	16	uimsbf
//	reserved	2	bslbf
//	version_number	5	uimsbf
//	current_next_indicator	1	bslbf
//	section_number	8	uimsbf
//	last_section_number	8	uimsbf
//
//
//	transport_stream_id	16	uimsbf
//	original_network_id	16	uimsbf
//	segment_last_section_number	8	uimsbf
//	last_table_id	8	uimsbf
//	for(i=0;i<N;i++){
//		event_id	16	uimsbf
//		start_time	40	bslbf
//		duration	24	uimsbf
//		running_status	3	uimsbf
//		free_CA_mode	1	bslbf
//		descriptors_loop_length	12	uimsbf
//		for(i=0;i<N;i++){
//			descriptor()
//		}
//	}
//----------------------------------
//	CRC_32	32	rpchof
//}

void parse_eit(struct TS_bits *bits)
{
	// common
	unsigned table_id = bits_get(bits, 8) ;
	bits_skip(bits, 4) ;
	unsigned section_len = bits_get(bits, 12) ;

	// specific
	unsigned service_id = bits_get(bits, 16) ;
	bits_skip(bits, 2) ;
	unsigned version = bits_get(bits, 5) ;
	unsigned current_next = bits_get(bits, 1) ;
	unsigned section = bits_get(bits, 8) ;
	unsigned last_section = bits_get(bits, 8) ;

	unsigned tsid = bits_get(bits, 16) ;
	unsigned net_id = bits_get(bits, 16) ;
	unsigned segment_last_section_number = bits_get(bits, 8) ;
	unsigned last_table_id = bits_get(bits, 8) ;

	int len1 = section_len ;

printf("  0x%02x [EIT] - service %d TSID %d (curr %d) len=%d\n", table_id, service_id, tsid, current_next, section_len) ;

	while (bits->buff_len > 12)
	{
		unsigned event_id = bits_get(bits, 16) ;
		unsigned mjd = bits_get(bits, 16) ;
		unsigned start = bits_get(bits, 24) ;
		unsigned duration = bits_get(bits, 24) ;

		unsigned running_status = bits_get(bits, 3) ;
		unsigned free_CA_mode = bits_get(bits, 1) ;
		int descriptors_loop_length = bits_get(bits, 12) ;

printf("  * 0x%02x [EIT] (service %d) Event %d [mjd 0x%04x start 0x%06x duration 0x%06x] : Running status = %d (desc len %d, payload left %d)\n",
		table_id, service_id,
		event_id, mjd, start, duration,
		running_status, descriptors_loop_length,
		bits->buff_len) ;

		int end_buff_len = bits->buff_len  - descriptors_loop_length ;
		while (bits->buff_len > end_buff_len)
		{
printf("    -> parse_desc() (loop len %d) [%d > %d]\n", descriptors_loop_length, bits->buff_len, end_buff_len);
			unsigned desc_len = parse_desc(bits) ;

			descriptors_loop_length -= (int)desc_len ;
printf("    (remain loop len %d)\n", descriptors_loop_length);
		}
	}
}
