
 # /*---------------------------------------------------------------------------------------------------*/
 # /* Remove the demux filter (specified via the file handle) */
int
dvb_del_demux (DVB *dvb, int fd)

	CODE:
		if (fd > 0)
		{
			// delete demux filter
			RETVAL = dvb_demux_remove_filter(dvb, fd) ;
		}
		else
		{
			RETVAL = -1 ;
		}

	OUTPUT:
       RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Set the DEMUX to add a new stream specified by it's pid. Returns file handle or negative if fail */
int
dvb_add_demux (DVB *dvb, unsigned int pid)

	CODE:
		// set demux
		RETVAL = dvb_demux_add_filter(dvb, pid) ;

	OUTPUT:
       RETVAL



 # /*---------------------------------------------------------------------------------------------------*/
 # /* Stream the raw TS data to a file (assumes frontend & demux are already set up  */
int
dvb_record (DVB *dvb, char *filename, int sec)
	CODE:
		if (sec <= 0)
	          croak ("Linux::DVB::DVBT::dvb_record requires a valid record length in seconds");


		// open dvr first
		RETVAL = dvb_dvr_open(dvb) ;

        // save stream
		if (RETVAL == 0)
		{
			RETVAL = write_stream(dvb, filename, sec) ;

			// close dvr
			dvb_dvr_release(dvb) ;
		}


	OUTPUT:
      RETVAL


 # /*---------------------------------------------------------------------------------------------------*/
 # /* Record a multiplex */
 #
 #	struct multiplex_file_struct {
 #		int								file;
 #		time_t 							start;
 #		time_t 							end;
 #	    unsigned int                    done;
 #	} ;
 #
 #	struct multiplex_pid_struct {
 #	    struct multiplex_file_struct	 *file_info ;
 #	    unsigned int                     pid;
 #	} ;
 #

int
dvb_record_demux (DVB *dvb, SV *multiplex_aref)

  INIT:
	unsigned 		num_entries ;
	int				i ;
	SV				**item ;
	SV 				**val;
	HV				*href ;
	char			*str ;

    AV 				*pid_array;
	unsigned 		num_pids ;
	int				j ;
	SV				**piditem ;

	struct multiplex_file_struct	*file_info ;
	struct multiplex_pid_struct		*pid_list ;
	unsigned						pid_list_length ;
	unsigned						pid_index;

	time_t 		now, start, end;
	int			file ;
	int rc ;

  CODE:

	if ((!SvROK(multiplex_aref))
	|| (SvTYPE(SvRV(multiplex_aref)) != SVt_PVAV))
	{
	 	croak("Linux::DVB::DVBT::dvb_record_demux requires a valid array ref") ;
	}

    // av_len returns -1 for empty. Returns maximum index number otherwise
	num_entries = av_len( (AV *)SvRV(multiplex_aref) ) + 1 ;
	if (num_entries <= 0)
	{
	 	croak("Linux::DVB::DVBT::dvb_record_demux requires a list of multiplex hashes") ;
	}

	// count number of entries (and check structure)
	pid_list_length = 0 ;

	for (i=0; i <= num_entries ; i++)
	{
		if ((item = av_fetch((AV *)SvRV(multiplex_aref), i, 0)) && SvOK (*item))
		{
  			if ( SvTYPE(SvRV(*item)) != SVt_PVHV )
  			{
 			 	croak("Linux::DVB::DVBT::dvb_record_demux requires a list of multiplex hashes") ;
 			}
 			href = (HV *)SvRV(*item) ;

 			// get pids
 			val = HVF(href, pids) ;
 			pid_array = (AV *) SvRV (*val);
 			num_pids = av_len(pid_array) + 1 ;

			pid_list_length += num_pids ;
		}
	}

	// create arrays
	now = time(NULL);
 	pid_list = (struct multiplex_pid_struct *)safemalloc( sizeof(struct multiplex_pid_struct) * pid_list_length);
 	file_info = (struct multiplex_file_struct *)safemalloc( sizeof(struct multiplex_file_struct) * num_entries );

	for (i=0, pid_index=0; i <= num_entries ; i++)
	{
		if ((item = av_fetch((AV *)SvRV(multiplex_aref), i, 0)) && SvOK (*item))
		{
 			href = (HV *)SvRV(*item) ;

 			val = HVF(href, destfile) ;
 			str = (char *)SvPV(*val, SvLEN(*val)) ;
			file = open(str, O_WRONLY | O_TRUNC | O_CREAT | O_LARGEFILE, 0666);
		    if (-1 == file) {

				fprintf(stderr,"open %s: %s\n",str,strerror(errno));
				croak("Linux::DVB::DVBT::dvb_record_demux failed to write to file") ;
		    }

			// create file info struct
		 	file_info[i].file = file ;

 			val = HVF(href, offset) ;
		 	file_info[i].start = now + SvIV (*val) ;

 			val = HVF(href, duration) ;
		 	file_info[i].end = file_info[i].start + SvIV (*val) ;


 			// get pids
 			val = HVF(href, pids) ;
 			pid_array = (AV *) SvRV (*val);
 			num_pids = av_len(pid_array) + 1 ;

 			for (j=0; j < num_pids ; j++, ++pid_index)
 			{
 				if ((piditem = av_fetch(pid_array, j, 0)) && SvOK (*piditem))
 				{
 					pid_list[pid_index].file_info = &file_info[i] ;
 					pid_list[pid_index].pid  = SvIV (*piditem) ;
 					pid_list[pid_index].done = 0 ;
 					pid_list[pid_index].pkts = 0 ;
 				}
 			}

		}
	}

 	// open dvr first
 	RETVAL = dvb_dvr_open(dvb) ;

     // save stream
 	if (RETVAL == 0)
 	{
 		RETVAL = write_stream_demux(dvb, pid_list, pid_index) ;

 		// close dvr
 		dvb_dvr_release(dvb) ;
 	}

 	// free up
 	for (i=0; i < num_entries ; i++)
 	{
 		if (file_info[i].file > 0)
 		{
 			close(file_info[i].file) ;
 		}
 	}
 	safefree(pid_list) ;
 	safefree(file_info) ;


  OUTPUT:
    RETVAL


