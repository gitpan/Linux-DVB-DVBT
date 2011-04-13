/*
 * ts_bits.c
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

#include "ts_bits.h"

/*=============================================================================================*/
// CONSTANTS
/*=============================================================================================*/
//#define USE_DVBSNOOP
#define USE_NEW

/*=============================================================================================*/
// MACROS
/*=============================================================================================*/

/*=============================================================================================*/
// FUNCTIONS
/*=============================================================================================*/

#ifdef USE_DVBSNOOP
long long getBits48 (uint8_t *buf, int byte_offset, int startbit, int bitlen);

/*
  -- get bits out of buffer (max 32 bit!!!)
  -- return: value
*/

unsigned long getBits (uint8_t *buf, int byte_offset, int startbit, int bitlen)
{
	uint8_t *b;
 unsigned long  v;
 unsigned long mask;
 unsigned long tmp_long;
 int           bitHigh;


 b = &buf[byte_offset + (startbit >> 3)];
 startbit %= 8;

 switch ((bitlen-1) >> 3) {
	 case -1:	// -- <=0 bits: always 0
		return 0L;
		break;

	case 0:		// -- 1..8 bit
 		tmp_long = (unsigned long)(
			(*(b  )<< 8) +  *(b+1) );
		bitHigh = 16;
		break;

	case 1:		// -- 9..16 bit
 		tmp_long = (unsigned long)(
		 	(*(b  )<<16) + (*(b+1)<< 8) +  *(b+2) );
		bitHigh = 24;
		break;

	case 2:		// -- 17..24 bit
 		tmp_long = (unsigned long)(
		 	(*(b  )<<24) + (*(b+1)<<16) +
			(*(b+2)<< 8) +  *(b+3) );
		bitHigh = 32;
		break;

	case 3:		// -- 25..32 bit
			// -- to be safe, we need 32+8 bit as shift range
		return (unsigned long) getBits48 (b, 0, startbit, bitlen);
		break;

	default:	// -- 33.. bits: fail, deliver constant fail value
		fprintf (stderr, " Error: getBits() request out of bound!!!! (report!!) \n");
		return (unsigned long) 0xFEFEFEFE;
		break;
 }

 startbit = bitHigh - startbit - bitlen;
 tmp_long = tmp_long >> startbit;
 mask     = (1ULL << bitlen) - 1;  // 1ULL !!!
 v        = tmp_long & mask;

 return v;
}






/*
  -- get bits out of buffer  (max 48 bit)
  -- extended bitrange, so it's slower
  -- return: value
 */

long long getBits48 (uint8_t *buf, int byte_offset, int startbit, int bitlen)
{
	uint8_t *b;
 unsigned long long v;
 unsigned long long mask;
 unsigned long long tmp;

 if (bitlen > 48) {
	fprintf(stderr," Error: getBits48() request out of bound!!!! (report!!) \n");
	return 0xFEFEFEFEFEFEFEFELL;
 }


 b = &buf[byte_offset + (startbit / 8)];
 startbit %= 8;


 // -- safe is 48 bitlen
 tmp = (unsigned long long)(
	 ((unsigned long long)*(b  )<<48) + ((unsigned long long)*(b+1)<<40) +
	 ((unsigned long long)*(b+2)<<32) + ((unsigned long long)*(b+3)<<24) +
	 (*(b+4)<<16) + (*(b+5)<< 8) + *(b+6) );

 startbit = 56 - startbit - bitlen;
 tmp      = tmp >> startbit;
 mask     = (1ULL << bitlen) - 1;	// 1ULL !!!
 v        = tmp & mask;

 return v;
}
#endif
/*=============================================================================================*/


/* ----------------------------------------------------------------------- */
void bits_free(struct TS_bits **bits)
{
struct TS_bits *bp = *bits ;

	if (bp)
	{
		free(bp) ;
	}
	*bits = NULL ;
}

/* ----------------------------------------------------------------------- */
struct TS_bits *bits_new(uint8_t *src, unsigned src_len)
{
struct TS_bits *bp ;

	// create struct
	bp = (struct TS_bits *)malloc(sizeof(struct TS_bits)) ;
	memset(bp, 0, sizeof(*bp));

	// init
	bp->buff_ptr = src ;
	bp->buff_len = src_len ;
	bp->start_bit = 0 ;

	return bp ;
}



#ifdef USE_DVBSNOOP
/* ----------------------------------------------------------------------- */
unsigned bits_get_dvbsnoop(struct TS_bits *bits, unsigned len)
{
unsigned int result = 0;
unsigned start_len = len + bits->start_bit ;

//printf("get_bits(len=%d) [0x%02x 0x%02x 0x%02x 0x%02x]\n", len, bits->buff_ptr[0], bits->buff_ptr[1], bits->buff_ptr[2], bits->buff_ptr[3]) ;
//printf(" + buff_len=%d, start=%d, start_len=%d (sl/8=%d)\n", bits->buff_len, bits->start_bit, start_len, start_len/8) ;

	result = (unsigned)getBits(bits->buff_ptr, 0, bits->start_bit, len) ;

	// update buffer
	bits->start_bit = start_len % 8 ;
	bits->buff_len -= start_len / 8 ;
	bits->buff_ptr += start_len / 8 ;

//printf("get_bits() : result = 0x%x\n", result) ;
//printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;
//printf("---\n") ;

    return result;
}
#else

#ifdef USE_NEW

/* ----------------------------------------------------------------------- */
unsigned bits_get_new(struct TS_bits *bits, unsigned len)
{
unsigned int result = 0;
unsigned start_len = len + bits->start_bit ;
unsigned mask ;
int left_shift ;
unsigned byte = 0 ;

	if (len==0)
		return 0 ;

if (len > 32)
{
	fprintf(stderr, "BUGGER! Request for > 32 bits!\n") ;
	exit(1) ;
}

if (bits->buff_len <= 0)
{
	fprintf(stderr, "BUGGER! Gone past the end of the buffer!\n") ;
	exit(1) ;
}

	if (len == 32)
	{
		mask = 0xffffffff ;
	}
	else
	{
		mask = (1 << len) -1 ;
	}

//printf("get_bits_new(len=%d) [0x%02x 0x%02x 0x%02x 0x%02x]\n", len, bits->buff_ptr[0], bits->buff_ptr[1], bits->buff_ptr[2], bits->buff_ptr[3]) ;
//printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;


	// We want to shift the "start" bit to the MS bit of the final length
	//
	// 0   s  7    - NOTE: start bit is numbered from MS = 0 to LS = 7
	// [  0   ]
	//
	//
	left_shift = (len-1) - (7-bits->start_bit) ;

//printf(" ++ left shift=%d\n", left_shift) ;
	if (left_shift >= 0)
	{

		while (left_shift >= 0)
		{
			result |= bits->buff_ptr[byte++] << left_shift ;
			left_shift -= 8 ;
//			printf(" ++ res=0x%x, left shift=%d\n", result, left_shift) ;
		}
	}
	if ((left_shift < 0) && (left_shift > -8))
	{
		result |= bits->buff_ptr[byte] >> -left_shift ;
//		printf(" ++ res=0x%x right shift\n", result) ;
	}

	result &= mask ;

	// update buffer
	bits->start_bit = start_len % 8 ;
	bits->buff_len -= start_len / 8 ;
	bits->buff_ptr += start_len / 8 ;

//printf("get_bits() : result = 0x%x\n", result) ;
//printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;
//printf("---\n") ;

    return result;
}

///* ----------------------------------------------------------------------- */
//unsigned bits_get_new2(struct TS_bits *bits, unsigned len)
//{
//uint64_t result = 0;
//unsigned start_len = len + bits->start_bit ;
//uint64_t mask ;
//int right_shift ;
//unsigned byte = 0 ;
//
//	if (len==0)
//		return 0 ;
//
//if (len > 32)
//{
//	fprintf(stderr, "BUGGER! Request for > 32 bits!\n") ;
//	exit(1) ;
//}
//
//if (bits->buff_len <= 0)
//{
//	fprintf(stderr, "BUGGER! Gone past the end of the buffer!\n") ;
//	exit(1) ;
//}
//
//	mask = ( (uint64_t)1 << len) -1 ;
//
////printf("get_bits_new(len=%d) [0x%02x 0x%02x 0x%02x 0x%02x]\n", len, bits->buff_ptr[0], bits->buff_ptr[1], bits->buff_ptr[2], bits->buff_ptr[3]) ;
////printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;
//
//
//	// Start by assuming all bits will fit into 32
//	result  = (uint64_t)bits->buff_ptr[0] << 32 ;
//	if (bits->buff_len >= 2)
//		result |= (uint64_t)bits->buff_ptr[1] << 24 ;
//	if (bits->buff_len >= 3)
//		result |= (uint64_t)bits->buff_ptr[2] << 16 ;
//	if (bits->buff_len >= 4)
//		result |= (uint64_t)bits->buff_ptr[3] << 8 ;
//	if (bits->buff_len >= 5)
//		result |= (uint64_t)bits->buff_ptr[4] ;
//
//
//
//	// We want to shift the "start" bit to the MS bit of the final length
//	//
//	// 0   s  7    - NOTE: start bit is numbered from MS = 0 to LS = 7
//	// [  0   ]
//	//
//	//
//	right_shift = 32+(7-bits->start_bit) - (len-1) ;
//	result >>= right_shift ;
//
//	result &= mask ;
//
//	// update buffer
//	bits->start_bit = start_len % 8 ;
//	bits->buff_len -= start_len / 8 ;
//	bits->buff_ptr += start_len / 8 ;
//
////printf("get_bits() : result = 0x%x\n", result) ;
////printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;
////printf("---\n") ;
//
//    return (unsigned)result;
//}



#else
/* ----------------------------------------------------------------------- */
unsigned bits_get_loop(struct TS_bits *bits, unsigned len)
{
unsigned int result = 0;
uint8_t bit;

//printf("get_bits(len=%d) [0x%02x 0x%02x 0x%02x 0x%02x]\n", len, bits->buff_ptr[0], bits->buff_ptr[1], bits->buff_ptr[2], bits->buff_ptr[3]) ;
//printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;

    while (len)
    {
//		printf(" + + len=%d, bufflen=%d\n", len, bits->buff_len) ;
		if (bits->buff_len <= 0)
		{
			fprintf(stderr, "BUGGER! Gone past the end of the buffer!\n") ;
			exit(1) ;
		}

		result <<= 1;
		bit      = 1 << (7 - (bits->start_bit % 8));

		result  |= (bits->buff_ptr[0] & bit) ? 1 : 0;

//		printf(" + + len=%d, bit=0x%02x, start=%d, result=0x%08x\n", len, bit, bits->start_bit, result) ;

		if (++bits->start_bit >= 8)
		{
			// next byte
			bits->start_bit = 0 ;
			--bits->buff_len ;
//			printf(" + + + next byte : buff len=%d, start=%d, before buff=0x%02x (@ %p)\n", bits->buff_len, bits->start_bit, bits->buff_ptr[0], bits->buff_ptr) ;
			++bits->buff_ptr ;
//			printf(" + + + after buff=0x%02x (@ %p)\n", bits->buff_ptr[0], bits->buff_ptr) ;
		}
		len--;
    }

//printf("get_bits() : result = 0x%x\n", result) ;
//printf(" + buff_len=%d, start=%d\n", bits->buff_len, bits->start_bit) ;
//printf("---\n") ;

    return result;
}
#endif
#endif




///* ----------------------------------------------------------------------- */
//unsigned bits_get(struct TS_bits *bits, unsigned len)
//{
//unsigned int result = 0;
//unsigned start_len = len + bits->start_bit ;
//unsigned mask ;
//
//if (len > 32)
//{
//	fprintf(stderr, "BUGGER! Request for > 32 bits!\n") ;
//	exit(1) ;
//}
//
//if (bits->buff_len <= 0)
//{
//	fprintf(stderr, "BUGGER! Gone past the end of the buffer!\n") ;
//	exit(1) ;
//}
//
//	mask = (1 << len) -1 ;
//
//	// Start by assuming all bits will fit into 32
//	result  = bits->buff_ptr[0] << 24 ;
//	if (bits->buff_len >= 2)
//		result |= bits->buff_ptr[1] << 16 ;
//	if (bits->buff_len >= 3)
//		result |= bits->buff_ptr[2] << 8 ;
//	if (bits->buff_len >= 4)
//		result |= bits->buff_ptr[3] ;
//
//	// check to see if we go over 32 bit boundary
//	if (start_len > 32)
//	{
//		//         start
//		//          v
//		// 0 1 2 .. 6 7                                         6 7
//		// [    0     ]  [   1   ]  [   2   ]  [   3   ]  [   4   ]
//		//          :------------------------------------------>
//		//                    len (=32)
//		// len=32    len=24
//		// [          ]
//		//
//		unsigned left_shift = (len-24) - (7 - bits->start_bit) ;
//		result <<= left_shift ;
//
//		unsigned byte = 0 ;
//		if (bits->buff_len >= 5)
//			byte = bits->buff_ptr[4] ;
//
//		byte >>= (7 - bits->start_bit) ;
//		result |= byte ;
//	}
//	else
//	{
//		//    start
//		//     v
//		// 0 1 2 3 .. 7
//		// [    0     ]  [   1   ]  [   2   ]  [   3   ]
//		//     :----------->|-------------------------->
//		//         len             right shift
//		//
//		result >>= (32 - start_len) ;
//	}
//	result &= mask ;
//
//	// update buffer
//	bits->start_bit = start_len % 8 ;
//	bits->buff_len += start_len / 8 ;
//
//    return result;
//}

unsigned bits_get(struct TS_bits *bits, unsigned len)
{
#ifdef USE_DVBSNOOP
	return bits_get_dvbsnoop(bits, len) ;
#else
#ifdef USE_NEW
	return bits_get_new(bits, len) ;
#else
	return bits_get_loop(bits, len) ;
#endif
#endif

}

/* ----------------------------------------------------------------------- */
void bits_skip(struct TS_bits *bits, unsigned len)
{
unsigned int result ;

	while (len > 32)
	{
		// chop into 32 bit chunkc
		result= bits_get(bits, 32) ;
		len -= 32 ;
	}
	result = bits_get(bits, len) ;
}


#ifdef TEST_BITS
static uint8_t data[] = {0xde, 0xfe, 0x51, 0x4f, 0x00, 0x3e, 0x66, 0x34, 0x12, 0x56, 0x78, 0x9a, 0x91, 0xa7} ;
//static unsigned lens[] = {3, 12, 32, 1, 7} ;
static unsigned lens[] = {4, 8, 32, 12, 4, 1, 1, 1, 1, 1, 5, 4, 2} ;
void main()
{
struct TS_bits *bits_d = bits_new(data, sizeof(data)) ;
struct TS_bits *bits_n = bits_new(data, sizeof(data)) ;
unsigned res_d, res_n ;
int i ;
unsigned num_bytes = sizeof(data) ;
unsigned num_lens = sizeof(lens) / sizeof(unsigned) ;

	printf("Data: ") ;
	for (i=0; i < num_bytes; i++)
	{
		printf("0x%02x ", data[i]);
	}
	printf("\n") ;

	for (i=0; i < num_lens; i++)
	{
		unsigned len = lens[i] ;

		res_d = bits_get_dvbsnoop(bits_d, len) ;
		res_n = bits_get_new2(bits_n, len) ;

		printf("len = %d : old=%x, new=%x", len, res_d, res_n) ;
		if (res_d != res_n) printf(" *** ERROR ***") ;
		printf("\n") ;

//		printf (" * old: start=%d, len=%s, ptr=%p\n", bits_d->start_bit, bits_d->buff_len, bits_d->buff_ptr) ;
//		printf (" * new: start=%d, len=%s, ptr=%p\n", bits_n->start_bit, bits_n->buff_len, bits_n->buff_ptr) ;
	}
}
#endif

#ifdef PROFILE_BITS
static uint8_t data[] = {0xde, 0xfe, 0x51, 0x4f, 0x00, 0x3e, 0x66, 0x34, 0x12, 0x56, 0x78, 0x9a, 0x91, 0xa7} ;
static unsigned lens[] = {4, 8, 32, 12, 4, 1, 1, 1, 1, 1, 5, 4, 2} ;
void main()
{
struct TS_bits *bits = bits_new(data, sizeof(data)) ;
unsigned res ;
int i;
uint64_t j, k ;
unsigned num_bytes = sizeof(data) ;
unsigned num_lens = sizeof(lens) / sizeof(unsigned) ;


for (k=0; k < (uint64_t)1000000000; k++)
{
	for (j=0; j < (uint64_t)1000000000; j++)
	{
		for (i=0; i < num_lens; i++)
		{
			unsigned len = lens[i] ;

#ifdef USE_NEW
			res = bits_get_new2(bits, len) ;
#else
			res = bits_get_dvbsnoop(bits, len) ;
#endif

			printf("len = %d : res=%x", len, res) ;
			printf("\n") ;

	//		printf (" * old: start=%d, len=%s, ptr=%p\n", bits_d->start_bit, bits_d->buff_len, bits_d->buff_ptr) ;
	//		printf (" * new: start=%d, len=%s, ptr=%p\n", bits_n->start_bit, bits_n->buff_len, bits_n->buff_ptr) ;
		}
	}
}

}
#endif

