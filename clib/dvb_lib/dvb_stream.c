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
#include "ts.h"
#include "dvb_error.h"

#define TIMEOUT_SECS	3

#ifdef PROFILE_STREAM

#undef BUFFSIZE
#define BUFFSIZE 188

#define BINS_TIME			10
#define clear_bins(bins)	memset(bins, 0, (BUFFSIZE+1)*sizeof(unsigned))
#define inc_bin(bins, bin)	if ((bin>=0) && (bin <= BUFFSIZE)) { ++bins[bin]; }

/* ----------------------------------------------------------------------- */
void show_bins(unsigned *bins)
{
unsigned bin ;

	printf("Read histogram: ") ;
	for (bin=0; bin <= BUFFSIZE; ++bin)
	{
		if (bins[bin])
		{
			printf("%d=%d, ", bin, bins[bin]) ;
		}
	}
	printf("\n") ;
}
#endif

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
		if (dvb_debug) fprintf(stderr,"reading %d bytes\n", *count);
		if (data_ready < 0)
		{
			//perror("read");
			RETURN_DVB_ERROR(ERR_SELECT);
		}
		else
		{
			//fprintf_timestamp(stderr,"timed out\n");
			RETURN_DVB_ERROR(ERR_TIMEOUT);
		}
#ifdef PROFILE_STREAM
perror("data ready error : ");
#endif
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
#ifdef PROFILE_STREAM
perror("read error : ");
#endif
		if (errno == EOVERFLOW)
		{
			// ignore overflow error
			status = ERR_OVERFLOW ;
			rc = 1 ;
		}
		else
		{
			// some problem - show frontend status
			if (-1 != ioctl(h->fdro, FE_READ_STATUS, &fe_status))
			{
				if (dvb_debug) fprintf_timestamp(stderr, ">>> tuning status == 0x%04x\n", fe_status) ;
			}
		}
	}

if (dvb_debug >= 3) fprintf(stderr, "getbuff(): request=%d read=%d\n", *count, rc) ;

	switch (rc) {
	case -1:
		//fprintf_timestamp(stderr,"reading %d bytes\n", count);
		//perror("read");
		RETURN_DVB_ERROR(ERR_READ);
	case 0:
		//fprintf_timestamp(stderr,"EOF\n");
		RETURN_DVB_ERROR(ERR_EOF);

	default:
		break;
	}
	return(status) ;
}

/* ----------------------------------------------------------------------- */
int write_stream(struct dvb_state *h, char *filename, int sec)
{
time_t start, end, now, prev;
char buffer[BUFFSIZE];
int file;
int count;
int rc, nwrite;
unsigned done ;

    if (sec <= 0)
    {
		//fprintf(stderr, "Invalid duration (%d)\n", sec);
    	RETURN_DVB_ERROR(ERR_DURATION);
    }

    if (-1 == h->dvro)
    {
		//fprintf(stderr,"dvr device not open\n");
		RETURN_DVB_ERROR(ERR_DVR_OPEN);
    }

    file = open(filename, O_WRONLY | O_TRUNC | O_CREAT | O_LARGEFILE, 0666);
    if (-1 == file) {
		//fprintf(stderr,"open %s: %s\n",filename,strerror(errno));
		RETURN_DVB_ERROR(ERR_FILE);
    }

    count = 0;
    start = time(NULL);
    end = sec + time(NULL);
	for (done=0; !done;)
	{
		rc = read(h->dvro, buffer, sizeof(buffer));
		switch (rc) {
		case -1:
			//perror("read");
			RETURN_DVB_ERROR(ERR_READ);
		case 0:
			//fprintf(stderr,"EOF\n");
			RETURN_DVB_ERROR(ERR_EOF);
		default:
			nwrite = write(file, buffer, rc);
			count += rc;
			break;
		}
		now = time(NULL);

		if (dvb_debug)
		{
			if (prev != now)
			{
				fprintf(stderr, "%d / %d : %d bytes\n", (int)(now-start), (int)(end-start), rc) ;
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


/* ----------------------------------------------------------------------- */
int write_stream_demux(struct dvb_state *h, struct multiplex_pid_struct *pid_list, unsigned num_entries)
{
time_t now, prev, end_time;
char buffer[BUFFSIZE];
char *bptr ;
int status, final_status;
int rc, wrc;
//unsigned sync ;
unsigned ts_pid, ts_err ;
unsigned pid_index ;
int running ;
//unsigned byte_num ;
int buffer_len ;
int bytes_read ;

#ifdef PROFILE_STREAM
unsigned read_bins[BUFFSIZE+1] ;
time_t bins_time ;
#endif

    if (-1 == h->dvro)
    {
//		fprintf(stderr,"dvr device not open\n");
		RETURN_DVB_ERROR(ERR_DVR_OPEN);
    }

    // make access to demux non-blocking
    setNonblocking(h->dvro) ;

    // sticky error
    final_status = 0 ;

#ifdef PROFILE_STREAM
    clear_bins(read_bins) ;
    bins_time = time(NULL) + BINS_TIME ;
#endif

	// find end time
    end_time = 0 ;
	for (pid_index=0; pid_index < num_entries; ++pid_index)
	{
		if (end_time < pid_list[pid_index].file_info->end)
		{
			end_time = pid_list[pid_index].file_info->end;
		}
	}

    // main loop
    running = num_entries ;
	buffer_len = 0 ;
	bptr = buffer ;
    while (running > 0)
    {
		// start of each packet
		now = time(NULL);

		// check for request for new bytes
		if (buffer_len < TS_PACKET_LEN)
		{
			// next packets
			bytes_read = BUFFSIZE ;
			status = getbuff(h, buffer, &bytes_read) ;

			// special case of buffer overflow - update counts then continue
			if (status == ERR_OVERFLOW)
			{
				// increment counts
				for (pid_index=0; pid_index < num_entries; ++pid_index)
				{
					if (!pid_list[pid_index].done)
					{
						pid_list[pid_index].overflows++;
					}
				}
				status = ERR_NONE ;

				// check for end
				if (now > end_time)
				{
					running = 0 ;
					break ;
				}
				continue ;
			}

			if (!final_status) final_status = status ;
			buffer_len = bytes_read ;
			bptr = buffer ;

			if (dvb_debug >= 10)
				fprintf(stderr, "Reload buffer : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

#ifdef PROFILE_STREAM
			inc_bin(read_bins, bytes_read) ;
#endif
		}


		if (dvb_debug >= 10)
			fprintf(stderr, "Start of loop : 0x%02x (bptr @ %p) %d bytes left\n", bptr[0], bptr, buffer_len) ;

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
			ts_err = bptr[1] & 0x80 ;
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
					fprintf(stderr, " + + PID %d : %"PRIu64" pkts (%"PRIu64" errors) : ",
							pid_list[pid_index].pid,
							pid_list[pid_index].pkts,
							pid_list[pid_index].errors
							) ;
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
									(int)(pid_list[pid_index].file_info->end - now)) ;
							}
						}
						else
						{
							fprintf(stderr, "starting in %d secs ...",
								(int)(pid_list[pid_index].file_info->start - now)) ;
						}
					}
					fprintf(stderr, " [buff len=%d]\n", buffer_len) ;
				}
			}

#ifdef PROFILE_STREAM
			if (now >= bins_time)
			{
				show_bins(read_bins) ;
				clear_bins(read_bins) ;
				bins_time = time(NULL) + BINS_TIME ;
			}

//			usleep(10000) ;
#endif

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
						wrc=write(pid_list[pid_index].file_info->file, bptr, TS_PACKET_LEN);

						// error count
						if (ts_err)
						{
							pid_list[pid_index].errors++;
						}

						// debug
						pid_list[pid_index].pkts++;

						if (dvb_debug >= 10)
							fprintf(stderr, " + + Written PID %u : total %"PRIu64" pkts (%"PRIu64" errors) : ",
									pid_list[pid_index].pid,
									pid_list[pid_index].pkts,
									pid_list[pid_index].errors
									) ;

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

