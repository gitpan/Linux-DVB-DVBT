/*
 * handle dvb devices
 * import vdr channels.conf files
 */

#include <features.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ioctl.h>

#include "dvb_lib.h"
#include "dvb_tune.h"
#include "dvb_stream.h"
#include "dvb_debug.h"

#define TIMEOUT_SECS	3
#define MAX_PID			0x1fff
#define ALL_PID			(MAX_PID+1)
#define NULL_PID		(ALL_PID+1)


// ISO 13818-1
#define SYNC_BYTE		0x47
#define TS_PACKET_LEN	188

// create a buffer that is a number of packets long
// (this is approx 4k)
#define BUFFSIZE		(22 * TS_PACKET_LEN)


// If large file support is not included, then make the value do nothing
#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

// ERRORS
#define ERR_DURATION		1
#define ERR_DVB_DEV			2
#define ERR_FILE			3
#define ERR_NOSYNC			4

#define ERR_READ			100
#define ERR_EOF				101
#define ERR_BUFFER_ZERO		102

#define ERR_SELECT			200
#define ERR_TIMEOUT			201




/* ----------------------------------------------------------------------- */
int write_stream(struct dvb_state *h, char *filename, int sec)
{
time_t start, end, now, prev;
char buffer[BUFFSIZE];
int file;
int count;
int rc;
unsigned done ;

    if (sec <= 0)
    {
		fprintf(stderr, "Invalid duration (%d)\n", sec);
		return(ERR_DURATION);
    }

    if (-1 == h->dvro)
    {
		fprintf(stderr,"dvr device not open\n");
		return(ERR_DVB_DEV);
    }

    file = open(filename, O_WRONLY | O_TRUNC | O_CREAT | O_LARGEFILE, 0666);
    if (-1 == file) {
		fprintf(stderr,"open %s: %s\n",filename,strerror(errno));
		return(ERR_FILE);
    }

    count = 0;
    start = time(NULL);
    end = sec + time(NULL);
	for (done=0; !done;)
	{
		rc = read(h->dvro, buffer, sizeof(buffer));
		switch (rc) {
		case -1:
			perror("read");
			return(ERR_READ);
		case 0:
			fprintf(stderr,"EOF\n");
			return(ERR_EOF);
		default:
			write(file, buffer, rc);
			count += rc;
			break;
		}
		now = time(NULL);

		if (dvb_debug)
		{
			if (prev != now)
			{
				fprintf(stderr, "%d / %d : %d bytes\n", now-start, end-start, rc) ;
				prev = now ;
			}
		}

		if (now >= end)
		{
			++done ;
			break;
		}
	}
    
    close(file);

    return 0;
}

#if 0
/* ----------------------------------------------------------------------- */
int write_stream_demux(struct dvb_state *h, struct multiplex_pid_struct *pid_list, unsigned num_entries)
{
time_t now, prev;
char buffer[BUFFSIZE];
char *bptr ;
int status;
int rc;
unsigned sync ;
unsigned ts_pid ;
unsigned pid_index ;
int running ;
unsigned byte_num ;
int buffer_len ;
int bytes_read ;

    if (-1 == h->dvro)
    {
		fprintf(stderr,"dvr device not open\n");
		return(ERR_DVB_DEV);
    }

    // make access to demux non-blocking
    setNonblocking(h->dvro) ;

    // main loop
    running = num_entries ;
    sync = 1 ;
    while (running > 0)
    {
		if (dvb_debug)
			fprintf(stderr, "waiting for sync...\n") ;

    	// wait for sync byte
    	bptr = buffer ;
		bytes_read = 1 ;
    	status = getbuff(h, buffer, &bytes_read) ;
    	if (status) return (status) ;
    	if (bytes_read <= 0) return (ERR_BUFFER_ZERO) ;

    	// wait for sync byte, but abort if we've waited for at least 4 packets and not found it
    	byte_num=0;
    	while ( (buffer[0] != SYNC_BYTE) && (byte_num < (4*TS_PACKET_LEN)) )
    	{
    		bytes_read = 1 ;
	    	status = getbuff(h, buffer, &bytes_read) ;
	    	if (status) return (status) ;
	    	if (bytes_read <= 0) return (ERR_BUFFER_ZERO) ;

	    	++byte_num ;
    	}
    	sync = 0 ;

    	// did we find it?
    	if (buffer[0] != SYNC_BYTE)
    	{
    		return(ERR_NOSYNC) ;
    	}

		if (dvb_debug >= 10)
			fprintf(stderr, "handling TS packets...(buffer @ %p)\n", buffer) ;

		// get rest of TS packet
		buffer_len = bytes_read ;
		bytes_read = (BUFFSIZE-1) ;
    	status = getbuff(h, &buffer[1], &bytes_read) ;
    	buffer_len += bytes_read ;
    	bptr = buffer ;
    	while ( (running>0) && !sync)
    	{
	    	if (status) return (status) ;
	    	if (buffer_len <= 0) return (ERR_BUFFER_ZERO) ;

			if (dvb_debug >= 10)
				fprintf(stderr, "Start of loop : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

    		// start of each packet
			now = time(NULL);

			// check sync byte
			if (bptr[0] != SYNC_BYTE)
			{
				// re-sync
				++sync ;

				if (dvb_debug >= 10)
					fprintf(stderr, "! Resync required : 0x%02x (bptr @ %p)\n", bptr[0], bptr) ;
			}
			else
			{
				/* decode header
				#	sync_byte 8 bslbf
				#
				#	transport_error_indicator 1 bslbf
				#	payload_unit_start_indicator 1 bslbf
				#	transport_priority 1 bslbf
				#	PID 13 uimsbf
				#
				#	transport_scrambling_control 2 bslbf
				#	adaptation_field_control 2 bslbf
				#	continuity_counter 4 uimsbf
				#
				#	if(adaptation_field_control = = '10' || adaptation_field_control = = '11'){
				#		adaptation_field()
				#	}
				#	if(adaptation_field_control = = '01' || adaptation_field_control = = '11') {
				#		for (i = 0; i < N; i++){
				#		data_byte 8 bslbf
				#		}
				#	}
				*/
				ts_pid = ((bptr[1] & 0x1f) << 8) | (bptr[2] & 0xff) & MAX_PID ;
				if (dvb_debug >= 10)
				{
					if (prev != now)
					{
						fprintf(stderr, "-> TS PID 0x%x (%u)\n", ts_pid, ts_pid) ;
					}
				}

				// search the pid list for a match (also keep done flags up to date - in case there are no packets for this pid!)
				for (pid_index=0; pid_index < num_entries; ++pid_index)
				{
					// debug display
					if (dvb_debug)
					{
						if (prev != now)
						{
							fprintf(stderr, " + + PID %d : %d pkts : ", pid_list[pid_index].pid, pid_list[pid_index].pkts) ;
							if (pid_list[pid_index].done)
							{
								fprintf(stderr, "complete") ;
							}
							else
							{
								if (now >= pid_list[pid_index].file_info->start)
								{
									if (now <= pid_list[pid_index].file_info->end)
									{
										fprintf(stderr, "recording (%d secs remaining)",
											pid_list[pid_index].file_info->end - now) ;
									}
								}
								else
								{
									fprintf(stderr, "starting in %d secs ...",
										pid_list[pid_index].file_info->start - now) ;
								}
							}
							fprintf(stderr, "\n") ;
						}
					}

					// skip if done
					if (!pid_list[pid_index].done)
					{
						// matching pid?
						if (ts_pid == pid_list[pid_index].pid)
						{
							// check start time
							if (now >= pid_list[pid_index].file_info->start)
							{
								// write this packet to the corresponding file
								write(pid_list[pid_index].file_info->file, bptr, TS_PACKET_LEN);

								// debug
								pid_list[pid_index].pkts++;

								if (dvb_debug >= 10)
									fprintf(stderr, " + + Written PID %d : total %d pkts : ", pid_list[pid_index].pid, pid_list[pid_index].pkts) ;

							}
						}

						// check end time - mark as done if elapsed
						if (now > pid_list[pid_index].file_info->end)
						{
							pid_list[pid_index].done = 1 ;
							--running ;
						}
					}
				} // for each pid

				// update buffer
				buffer_len -= TS_PACKET_LEN ;
				bptr += TS_PACKET_LEN ;
				if (buffer_len < TS_PACKET_LEN)
				{
					// next packets
					bytes_read = BUFFSIZE ;
			    	status = getbuff(h, buffer, &bytes_read) ;
			    	buffer_len = bytes_read ;
			    	bptr = buffer ;

					if (dvb_debug >= 10)
						fprintf(stderr, "Reload buffer : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

				}

			} // if sync

			prev = now ;

			if (dvb_debug >= 10)
				fprintf(stderr, "End of loop : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;


    	} // while in sync

    } // while running

    return 0;
}
#endif


/* ----------------------------------------------------------------------- */
int write_stream_demux(struct dvb_state *h, struct multiplex_pid_struct *pid_list, unsigned num_entries)
{
time_t now, prev;
char buffer[BUFFSIZE];
char *bptr ;
int status, final_status;
int rc;
//unsigned sync ;
unsigned ts_pid ;
unsigned pid_index ;
int running ;
//unsigned byte_num ;
int buffer_len ;
int bytes_read ;

    if (-1 == h->dvro)
    {
		fprintf(stderr,"dvr device not open\n");
		return(ERR_DVB_DEV);
    }

    // make access to demux non-blocking
    setNonblocking(h->dvro) ;

    // sticky error
    final_status = 0 ;

    // main loop
    running = num_entries ;
//    sync = 1 ;
	buffer_len = 0 ;
	bptr = buffer ;
    while (running > 0)
    {
		// check for request for new bytes
		if (buffer_len < TS_PACKET_LEN)
		{
			// next packets
			bytes_read = BUFFSIZE ;
			status = getbuff(h, buffer, &bytes_read) ;
			if (!final_status) final_status = status ;
			buffer_len = bytes_read ;
			bptr = buffer ;

			if (dvb_debug >= 10)
				fprintf(stderr, "Reload buffer : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

		}


		if (dvb_debug >= 10)
			fprintf(stderr, "Start of loop : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

		// start of each packet
		now = time(NULL);

		// reset to a value that won't ever match
		ts_pid = NULL_PID ;

		// check sync byte
		while ( (bptr[0] != SYNC_BYTE) && (buffer_len > 0) )
		{
			if (dvb_debug >= 10)
				fprintf(stderr, "! Searching for sync : 0x%02x (bptr @ %p) len=%d\n", bptr[0], bptr, buffer_len) ;

			++bptr ;
			--buffer_len ;
		}

		// only process if we have a packet's worth
		if (buffer_len >= TS_PACKET_LEN)
		{
			/* decode header
			#	sync_byte 8 bslbf
			#
			#	transport_error_indicator 1 bslbf
			#	payload_unit_start_indicator 1 bslbf
			#	transport_priority 1 bslbf
			#	PID 13 uimsbf
			#
			#	transport_scrambling_control 2 bslbf
			#	adaptation_field_control 2 bslbf
			#	continuity_counter 4 uimsbf
			#
			#	if(adaptation_field_control = = '10' || adaptation_field_control = = '11'){
			#		adaptation_field()
			#	}
			#	if(adaptation_field_control = = '01' || adaptation_field_control = = '11') {
			#		for (i = 0; i < N; i++){
			#		data_byte 8 bslbf
			#		}
			#	}
			*/
			ts_pid = ((bptr[1] & 0x1f) << 8) | (bptr[2] & 0xff) & MAX_PID ;
			if (dvb_debug >= 10)
			{
				if (prev != now)
				{
					fprintf(stderr, "-> TS PID 0x%x (%u)\n", ts_pid, ts_pid) ;
				}
			}
		}

		// search the pid list for a match (also keep done flags up to date - in case there are no packets for this pid!)
		for (pid_index=0; pid_index < num_entries; ++pid_index)
		{
			// debug display
			if (dvb_debug)
			{
				if (prev != now)
				{
					fprintf(stderr, " + + PID %d : %d pkts : ", pid_list[pid_index].pid, pid_list[pid_index].pkts) ;
					if (pid_list[pid_index].done)
					{
						fprintf(stderr, "complete") ;
					}
					else
					{
						if (now >= pid_list[pid_index].file_info->start)
						{
							if (now <= pid_list[pid_index].file_info->end)
							{
								fprintf(stderr, "recording (%d secs remaining)",
									pid_list[pid_index].file_info->end - now) ;
							}
						}
						else
						{
							fprintf(stderr, "starting in %d secs ...",
								pid_list[pid_index].file_info->start - now) ;
						}
					}
					fprintf(stderr, " [buff len=%d]\n", buffer_len) ;
				}
			}

			// skip if done
			if (!pid_list[pid_index].done)
			{
				// matching pid?
				if (ts_pid == pid_list[pid_index].pid)
				{
					// check start time
					if (now >= pid_list[pid_index].file_info->start)
					{
						// write this packet to the corresponding file
						write(pid_list[pid_index].file_info->file, bptr, TS_PACKET_LEN);

						// debug
						pid_list[pid_index].pkts++;

						if (dvb_debug >= 10)
							fprintf(stderr, " + + Written PID %d : total %d pkts : ", pid_list[pid_index].pid, pid_list[pid_index].pkts) ;

					}
				}

				// check end time - mark as done if elapsed
				if (now > pid_list[pid_index].file_info->end)
				{
					pid_list[pid_index].done = 1 ;
					--running ;
				}
			}
		} // for each pid

		// update buffer
		if (buffer_len >= TS_PACKET_LEN)
		{
			buffer_len -= TS_PACKET_LEN ;
			bptr += TS_PACKET_LEN ;
		}

		prev = now ;

		if (dvb_debug >= 10)
			fprintf(stderr, "End of loop : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

    } // while running

    return final_status;
}

/* ----------------------------------------------------------------------- */
int getbuff(struct dvb_state *h, char *buffer, int *count)
{
int rc ;
int status ;
int data_ready ;
fe_status_t  fe_status  = 0;


	status = 0 ;

	// wait for data (or time out)
	data_ready = input_timeout(h->dvro, TIMEOUT_SECS) ;
	if (data_ready != 1)
	{
		fprintf(stderr,"reading %d bytes\n", *count);
		if (data_ready < 0)
		{
			perror("read");
			return(ERR_SELECT);
		}
		else
		{
			fprintf_timestamp(stderr,"timed out\n");
			return(ERR_TIMEOUT);
		}
	}

	// got to here so data is available
	rc = read(h->dvro, buffer, *count);

	// return actual read amount
	*count = 0 ;
	if (rc > 0)
	{
		*count = rc ;
	}
	else
	{
		// some problem - show frontend status
	    if (-1 != ioctl(h->fdro, FE_READ_STATUS, &fe_status))
	    {
			fprintf_timestamp(stderr, ">>> tuning status == 0x%04x\n", fe_status) ;
	    }
	}
	
if (dvb_debug >= 3) fprintf(stderr, "getbuff(): request=%d read=%d\n", *count, rc) ;
	
	switch (rc) {
	case -1:
		fprintf_timestamp(stderr,"reading %d bytes\n", count);
		perror("read");
		return(ERR_READ);
	case 0:
		fprintf_timestamp(stderr,"EOF\n");
		return(ERR_EOF);

	default:
		break;
	}
	return(status) ;
}

/* ----------------------------------------------------------------------- */
// Wait for data ready or timeout
int
input_timeout (int filedes, unsigned int seconds)
{
   fd_set set;
   struct timeval timeout;

   /* Initialize the file descriptor set. */
   FD_ZERO (&set);
   FD_SET (filedes, &set);

   /* Initialize the timeout data structure. */
   timeout.tv_sec = seconds;
   timeout.tv_usec = 0;

   /* select returns 0 if timeout, 1 if input available, -1 if error. */
   return TEMP_FAILURE_RETRY (select (FD_SETSIZE,
                                      &set, NULL, NULL,
                                      &timeout));
}


