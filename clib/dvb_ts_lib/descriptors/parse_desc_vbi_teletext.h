/*
 * parse_desc_vbi_teletext.h
 *
 *  Created by: si_desc.pl
 *  Created on: 20-May-2011
 *      Author: sdprice1
 */

#ifndef PARSE_DESC_VBI_TELETEXT_H_
#define PARSE_DESC_VBI_TELETEXT_H_

/*=============================================================================================*/
// USES
/*=============================================================================================*/
#include "desc_structs.h"
#include "ts_structs.h"

/*=============================================================================================*/
// CONSTANTS
/*=============================================================================================*/

/*=============================================================================================*/
// MACROS
/*=============================================================================================*/

/*=============================================================================================*/
// STRUCTS
/*=============================================================================================*/

// VBI_teletext_descriptor() {
//  descriptor_tag   8 uimsbf
//  descriptor_length  8 uimsbf
//   for (i=0;i<N;i++) {
//   ISO_639_language_code  24 bslbf
//   teletext_type  5 uimsbf
//  teletext_magazine_number  3 uimsbf
//   teletext_page_number  8 uimsbf
//  }
// }

struct VTD_entry {
	// linked list
	struct list_head next ;

	unsigned ISO_639_language_code ;                  	   // 24 bits
	unsigned teletext_type ;                          	   // 5 bits
	unsigned teletext_magazine_number ;               	   // 3 bits
	unsigned teletext_page_number ;                   	   // 8 bits
} ;

struct Descriptor_vbi_teletext {

	// linked list
	struct list_head next ;

	// contents
	unsigned descriptor_tag ;                         	   // 8 bits
	unsigned descriptor_length ;                      	   // 8 bits
	
	// linked list of VTD_entry
	struct list_head vtd_array ;
	
};

	
/*=============================================================================================*/
// FUNCTIONS
/*=============================================================================================*/

/* ----------------------------------------------------------------------- */
void print_vbi_teletext(struct Descriptor_vbi_teletext *vtd, int level) ;
struct Descriptor *parse_vbi_teletext(struct TS_bits *bits, unsigned tag, unsigned len) ;
void free_vbi_teletext(struct Descriptor_vbi_teletext *vtd) ;

#endif /* PARSE_DESC_VBI_TELETEXT_H_ */

