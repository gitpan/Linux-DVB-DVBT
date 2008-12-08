/*
 * Generic SI parsing
 */


/* ----------------------------------------------------------------------- */


/* ----------------------------------------------------------------------- */




typedef struct {
	unsigned int	start_bit;
	unsigned int	num_bits;
} Parse_data ;

typedef enum {ival, string, desc} Info_type ;
typedef union {
	unsigned int	ival ;
	char *			string ;
	void *			ref ;
} Info_val ;

typedef struct {
//	unsigned int 	skip_bits;	// = number of bits to skip after previous field
	unsigned int 	num_bits;	// = number of bits for this field
	Info_type		type ;
	Into_val		value ;
	unsigned int	valid ;
	// add conversion routine? mjd?

} Parse_info ;

#define INFO_IDX_ID		0
#define INFO_IDX_LEN	4



#define GENERIC_PARSE	0xFF

#define PARSE_ID		0
#define PARSE_LEN		4

//Parse_data generic_si_tables[] = {
//
//		[PARSE_ID] 	= {0, 	8},
//		[PARSE_LEN]	= {12, 	12},
//
//};

Parse_data si_tables[][256] = {
//	[0x00] = {},

//	[GENERIC_PARSE] = generic_si_tables,

	[GENERIC_PARSE] = {
		[PARSE_ID] 	= {0, 	8},
		[PARSE_LEN]	= {12, 	12},
	}
};

//Parse_data generic_desc_tables[] = {
//
//		[PARSE_ID] 	= {0, 	8},
//		[PARSE_LEN]	= {8, 	8},
//
//};

Parse_data si_descs[][256] = {
//	[0x00] = {},

//	[GENERIC_PARSE] = generic_desc_tables,
	[GENERIC_PARSE] = {
		[PARSE_ID] 	= {/*start_bit*/0, 	/*num_bits*/8},
		[PARSE_LEN]	= {/*start_bit*/8, 	/*num_bits*/8},
	}
};


/* ----------------------------------------------------------------------- */
static int parse_entry(Parse_info *parse_info, int *bit_num, unsigned char *data, int data_len, int verbose)
{
	// first check length of data
	if (data_len > (*bit_num + parse_info->num_bits))
	{
		switch(parse_info->num_bits)
		{
		case ival :
		    parse_info->value.ival = mpeg_getbits(data, *bit_num, parse_info->num_bits);
		    parse_info->valid = 1 ;

		    *bit_num += parse_info->num_bits ;
			break ;

		case string :
			break ;

		case desc :
			break ;
		}
	}
	else
	{
		fprintf(stderr, "Bugger: run out of bits!\n") ;
	}


}

/* ----------------------------------------------------------------------- */
static int last_seen = 0 ;
static int parse_psi(Parse_info *parse_info, unsigned int num_items, unsigned char *data, int data_len, int verbose)
{
int table ;
int length ;
int parse_idx ;
int bit_num ;

	// Get fixed values first
	table = parse_info[INFO_IDX_ID].value.ival ;
	length = parse_info[INFO_IDX_LEN].value.ival ;

	// Cycle through array processing those items not yet done
	bit_num=0;
	for (parse_idx=0; parse_idx<num_items; ++parse_idx)
	{
		// skip if already processed
		if (!parse_info[parse_idx].valid)
		{
			// process this entry
			parse_entry(parse_info[parse_idx], &bit_num, data, data_len, verbose) ;
		}
		else
		{
			// move to next bit
			bit_num += parse_info[parse_idx].num_bits ;
		}
	}



	int tab,pnr,version,current,len;
    int j,dlen,tsid,nid,part,parts,seen;
    struct epgitem *epg;
    int id,mjd,start,length;

    tab     = mpeg_getbits(data, 0,8);
    len     = mpeg_getbits(data,12,12) + 3 - 4;
    pnr     = mpeg_getbits(data,24,16);
    version = mpeg_getbits(data,42,5);
    current = mpeg_getbits(data,47,1);
    if (!current)
	return len+4;

    part  = mpeg_getbits(data,48, 8);
    parts = mpeg_getbits(data,56, 8);
    tsid  = mpeg_getbits(data,64,16);
    nid   = mpeg_getbits(data,80,16);
    seen  = eit_seen(tab,pnr,tsid,part,version);
last_seen = seen ;
    if (seen)
	return len+4;

    eit_last_new_record = time(NULL);
    if (verbose>1)
	fprintf(stderr,
		"ts [eit]: tab 0x%x pnr %3d ver %2d tsid %d nid %d [%d/%d]\n",
		tab, pnr, version, tsid, nid, part, parts);

    j = 112;
    while (j < len*8) {
	id     = mpeg_getbits(data,j,16);
	mjd    = mpeg_getbits(data,j+16,16);
	start  = mpeg_getbits(data,j+32,24);
	length = mpeg_getbits(data,j+56,24);
	epg = epgitem_get(tsid,pnr,id);
	epg->start  = decode_mjd_time(mjd,start);
	epg->stop   = epg->start + decode_length(length);
	epg->updated++;

	if (verbose > 2)
	    fprintf(stderr,"  id %d mjd %d time %06x du %06x r %d ca %d  #",
		    id, mjd, start, length,
		    mpeg_getbits(data,j+80,3),
		    mpeg_getbits(data,j+83,1));
	dlen = mpeg_getbits(data,j+84,12);
	j += 96;
	parse_eit_desc(data + j/8, dlen, epg, verbose);
	if (verbose > 3) {
	    fprintf(stderr,"\n");
	    fprintf(stderr,"    n: %s\n",epg->name);
	    fprintf(stderr,"    s: %s\n",epg->stext);
	    fprintf(stderr,"    e: %s\n",epg->etext);
	    fprintf(stderr,"\n");
	}
	j += 8*dlen;
    }

    if (verbose > 1)
	fprintf(stderr,"\n");
    return len+4;
}


/* ----------------------------------------------------------------------- */
static int get_bits(unsigned char *data, unsigned int start, int num_bits, int data_len)
{
int bits ;

	return bits ;
}


/* ----------------------------------------------------------------------- */
static Parse_info *get_parse_info(Parse_data **parse_ptr, unsigned char *data, unsigned int data_len)
{
Parse_info *parse_info ;

	// Use default parse data to get id and length for this table/descriptor
	int id = get_bits(data, parse_ptr[GENERIC_PARSE][PARSE_ID].start_bit, parse_ptr[GENERIC_PARSE][PARSE_ID].num_bits, data_len) ;
	int length = get_bits(data, parse_ptr[GENERIC_PARSE][PARSE_LEN].start_bit, parse_ptr[GENERIC_PARSE][PARSE_LEN].num_bits, data_len) ;

	// Create parse info based on the id
//	parse_info = malloc() ;

	return (parse_info) ;
}


/* ----------------------------------------------------------------------- */
// PUBLIC
/* ----------------------------------------------------------------------- */

/* ----------------------------------------------------------------------- */
int parse_psi_desc(unsigned char *data, unsigned int data_len, int verbose)
{
Parse_info *parse_info ;

	// Get parsing information
	parse_info = get_parse_info(si_descs, data, data_len) ;

	// Do parsing
//	parse_si(parse_info, data, data_len) ;

}

/* ----------------------------------------------------------------------- */
int parse_psi_table(unsigned char *data, unsigned int data_len, int verbose)
{
Parse_info *parse_info ;

	// Get parsing information
	parse_info = get_parse_info(si_tables, data, data_len) ;

	// Do parsing
	parse_si(parse_info, data, data_len) ;

}

