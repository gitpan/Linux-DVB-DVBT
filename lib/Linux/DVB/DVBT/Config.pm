package Linux::DVB::DVBT::Config ;

=head1 NAME

Linux::DVB::DVBT::Config - DVBT configuration functions

=head1 SYNOPSIS

	use Linux::DVB::DVBT::Config ;
  

=head1 DESCRIPTION

Module provides a set of configuration routines used by the DVBT module. It is unlikely that you will need to access these functions directly, but
you can if you wish.

=cut


use strict ;

our $VERSION = '2.06' ;
our $DEBUG = 0 ;

our $DEFAULT_CONFIG_PATH = '/etc/dvb:~/.tv' ;

use File::Path ;
use File::Spec ;

my %FILES = (
	'ts'	=> "dvb-ts",
	'pr'	=> "dvb-pr",
) ;

my %NUMERALS = (
	'one'	=> 1,
	'two'	=> 2,
	'three'	=> 3,
	'four'	=> 4,
	'five'	=> 5,
	'six'	=> 6,
	'seven'	=> 7,
	'eight'	=> 8,
	'nine'	=> 9,
) ;


#============================================================================================

=head2 Functions

=over 4

=cut



#----------------------------------------------------------------------

=item B<find_tsid($frequency, $tuning_href)>

Given a frequency, find the matching TSID.

$tuning_href is the HASH returned by L<Linux::DVB::DVBT::get_tuning_info()|lib::Linux::DVB::DVBT/get_tuning_info()>.

=cut

sub find_tsid
{
	my ($frequency, $tuning_href) = @_ ;
	my $tsid ;

#	'ts' => 
#	      4107 =>
#	        { 
#	          tsid => 4107,   
#			  frequency => 57800000,            
#	          ...
#	        },

	foreach my $this_tsid (keys %{$tuning_href->{'ts'}})
	{
		if ($frequency == $tuning_href->{'ts'}{$this_tsid}{'frequency'})
		{
			$tsid = $this_tsid ;
			last ;
		}
	}
	return $tsid ;
}

#----------------------------------------------------------------------

=item B<tsid_params($tsid, $tuning_href)>

Given a tsid, return the frontend params (or undef). The frontend params HASH
contain the information used to tune the frontend i.e. this is the transponder
(TSID) information. It corresponds to the matching 'ts' entry in the tuning info
HASH.

$tuning_href is the HASH returned by L<Linux::DVB::DVBT::get_tuning_info()|lib::Linux::DVB::DVBT/get_tuning_info()>.

=cut

sub tsid_params
{
	my ($tsid, $tuning_href) = @_ ;

	my $params_href ;

#	'ts' => 
#	      4107 =>
#	        { 
#	          tsid => 4107,   
#			  frequency => 57800000,            
#	          ...
#	        },

	if ($tsid && exists($tuning_href->{'ts'}{$tsid}))
	{
		$params_href = $tuning_href->{'ts'}{$tsid} ;
	}

	return $params_href ;
}

#----------------------------------------------------------------------

=item B<chan_from_pid($tsid, $pid, $tuning_href)>

Given a tsid and pid, find the matching channel information and returns the 
program HASH ref if found. This corresponds to the matching 'pr' entry in the tuning
info HASH.

$tuning_href is the HASH returned by L<Linux::DVB::DVBT::get_tuning_info()|lib::Linux::DVB::DVBT/get_tuning_info()>.

=cut

sub chan_from_pid
{
	my ($tsid, $pid, $tuning_href) = @_ ;
	my $pr_href ;
	
	# skip PAT
	return $pr_href unless $pid ;

#	'pr' =>
#	      BBC ONE => 
#	        {
#	          pnr => 4171,
#	          tsid => 4107,
#	          tuned_freq => 57800000,
#	          ...
#	        },

	foreach my $chan (keys %{$tuning_href->{'pr'}})
	{
		if ($tsid == $tuning_href->{'pr'}{$chan}{'tsid'})
		{
			foreach my $stream (qw/video audio teletext subtitle/)
			{
				if ($pid == $tuning_href->{'pr'}{$chan}{$stream})
				{
					$pr_href = $tuning_href->{'pr'}{$chan} ;
					last ;
				}
			}
			last if $pr_href ;

			# check other audio
			my @audio = audio_list( $tuning_href->{'pr'}{$chan} ) ;
			foreach (@audio)
			{
				if ($pid == $_)
				{
					$pr_href = $tuning_href->{'pr'}{$chan} ;
					last ;
				}
			}
		}
		
		last if $pr_href ;
	}

	return $pr_href ;
}

#----------------------------------------------------------------------

=item B<pid_info($pid, $tuning_href)>

Given a pid, find the matching channel & TSID information

Returns an array of HASH entries, each HASH containing the stream type (video, audio, subtitle, or
teletext), along with a copy of the associated program information (i.e. the matching 'pr' entry from the
tuning info HASH):

	@pid_info = [
		{
			  'pidtype' => video, audio, subtitle, teletext
		     pnr => 4171,
		     tsid => 4107,
		     tuned_freq => 57800000,
		          ...
		},
		...
	]


$tuning_href is the HASH returned by L<Linux::DVB::DVBT::get_tuning_info()|lib::Linux::DVB::DVBT/get_tuning_info()>.

=cut

sub pid_info
{
	my ($pid, $tuning_href) = @_ ;

print "pid_info(pid=\"$pid\")\n" if $DEBUG ;

	my @pid_info ;
	
	# skip PAT
	return @pid_info unless $pid ;
	
	foreach my $chan (keys %{$tuning_href->{'pr'}})
	{
		my $tsid = $tuning_href->{'pr'}{$chan}{'tsid'} ;
		
		# program
		my @chan_pids ;
		foreach my $stream (qw/video audio teletext subtitle/)
		{
			push @chan_pids, [$stream, $tuning_href->{'pr'}{$chan}{$stream}] ;
		}
		
		# extra audio
		my @audio = audio_list( $tuning_href->{'pr'}{$chan} ) ;
		foreach (@audio)
		{
			push @chan_pids, ['audio', $_] ;
		}
		
		# SI
		foreach my $si (qw/pmt/)
		{
			push @chan_pids, [uc $si, $tuning_href->{'pr'}{$chan}{$si}] ;
		}
		

		# check pids
		foreach my $aref (@chan_pids)
		{
			if ($pid == $aref->[1])
			{
print " + pidtype=$aref->[0]\n" if $DEBUG ;
				push @pid_info, {
					%{$tuning_href->{'pr'}{$chan}},
					'pidtype'		=> $aref->[0],
					
					# keep ref to program HASH (used by downstream functions)  
					'demux_params'	=> $tuning_href->{'pr'}{$chan},
				} ;
			}
		}
	}

	return @pid_info ;
}

#----------------------------------------------------------------------

=item B<find_channel($channel_name, $tuning_href)>

Given a channel name, do a "fuzzy" search and return an array containing params:

	($frontend_params_href, $demux_params_href)

$demux_params_href HASH ref are of the form:

	        {
	          pnr => 4171,
	          tsid => 4107,
	          tuned_freq => 57800000,
	          ...
	        },
	        
(i.e. $tuning_href->{'pr'}{$channel_name})

$frontend_params_href HASH ref are of the form:

	        { 
	          tsid => 4107,   
			  frequency => 57800000,            
	          ...
	        },
	
(i.e. $tuning_href->{'ts'}{$tsid} where $tsid is TSID for the channel)
	 
$tuning_href is the HASH returned by L<Linux::DVB::DVBT::get_tuning_info()|lib::Linux::DVB::DVBT/get_tuning_info()>.

=cut

sub find_channel
{
	my ($channel_name, $tuning_href) = @_ ;
	
	my ($frontend_params_href, $demux_params_href) ;

	## Look for channel info
	print STDERR "find $channel_name ...\n" if $DEBUG ;
	
	my $found_channel_name = _channel_search($channel_name, $tuning_href->{'pr'}) ;
	if ($found_channel_name)
	{
		$demux_params_href = $tuning_href->{'pr'}{$found_channel_name} ;
	}
					
	## If we've got the channel, look up it's frontend settings
	if ($demux_params_href)
	{
		my $tsid = $demux_params_href->{'tsid'} ;
		$frontend_params_href = {
			%{$tuning_href->{'ts'}{$tsid}},
			'tsid'	=> $tsid,
		} ;
	}

	return ($frontend_params_href, $demux_params_href) ;
}


#----------------------------------------------------------------------
# 
sub _channel_search
{
	my ($channel_name, $search_href) = @_ ;
	
	my $found_channel_name ;
	
	# start by just seeing if it's the correct name...
	if (exists($search_href->{$channel_name}))
	{
		return $channel_name ;
	}
	else
	{
		## Otherwise, try finding variations on the channel name
		my %search ;

		$channel_name = lc $channel_name ;
		
		# lower-case, no spaces
		my $srch = $channel_name ;
		$srch =~ s/\s+//g ;
		$search{$srch}=1 ;

		# lower-case, replaced words with numbers, no spaces
		$srch = $channel_name ;
		foreach my $num (keys %NUMERALS)
		{
			$srch =~ s/\b($num)\b/$NUMERALS{$num}/ge ;
		}
		$srch =~ s/\s+//g ;
		$search{$srch}=1 ;

		# lower-case, replaced numbers with words, no spaces
		$srch = $channel_name ;
		foreach my $num (keys %NUMERALS)
		{
print STDERR " -- $srch - replace $NUMERALS{$num} with $num..\n" if $DEBUG>3 ;
			$srch =~ s/($NUMERALS{$num})\b/$num/ge ;
print STDERR " -- -- $srch\n" if $DEBUG>3 ;
		}
		$srch =~ s/\s+//g ;
		$search{$srch}=1 ;

		print STDERR " + Searching tuning info [", keys %search, "]...\n" if $DEBUG>2 ;
		
		foreach my $chan (keys %$search_href)
		{
			my $srch_chan = lc $chan ;
			$srch_chan =~ s/\s+//g ;
			
			foreach my $search (keys %search)
			{
				print STDERR " + + checking $search against $srch_chan \n" if $DEBUG>2 ;
				if ($srch_chan eq $search)
				{
					$found_channel_name = $chan ;
					print STDERR " + found $channel_name\n" if $DEBUG ;
					last ;
				}
			}
			
			last if $found_channel_name ;
		}
	}
	
	return $found_channel_name ;
}




#----------------------------------------------------------------------

=item B<audio_pids($demux_params_href, $language_spec, $pids_aref)>

Process the demux parameters and a language specifier to return the list of audio
streams required. 

demux_params are of the form:

	        {
	          pnr => 4171,
	          tsid => 4107,
	          tuned_freq => 57800000,
	          ...
	        },

(i.e. $tuning_href->{'pr'}{$channel_name})

	
Language specifier string is in the format:

=over 4

=item a)

Empty string : just return the default audio stream pid

=item b)

Comma/space seperated list of one or more language names : returns the audio stream pids for all that match (does not necessarily include default stream)

=back
	
If the list in (b) contains a '+' character (normally at the start) then the default audio stream is automatically included in teh list, and the 
extra streams are added to it.
	
For example, if a channel has the following audio details: eng:100 eng:101 fra:102 deu:103
Then the following specifications result in the lists as shown:

=over 4

=item *	

"" => (100)

=item *	

"eng deu" => (100, 103)

=item *	

"+eng fra" => (100, 101, 102)

=back
	
Note that the language names are not case sensitive


=cut

sub audio_pids
{
	my ($demux_params_href, $language_spec, $pids_aref) = @_ ;
	my $error = 0 ;
	
print "audio_pids(lang=\"$language_spec\")\n" if $DEBUG ;

	my $audio_pid = $demux_params_href->{'audio'} ;
	
	## simplest case is no language spec
	$language_spec ||= "" ;
	if (!$language_spec)
	{
print " + simplest case - add default audio $audio_pid\n" if $DEBUG ;

		push @$pids_aref, $audio_pid ;
		return 0 ;		
	}

	# split details
	my @audio_details ;
	my $details = $demux_params_href->{'audio_details'} ;
print "audio_details=\"$details\")\n" if $DEBUG ;
	while ($details =~ m/(\S+):(\d+)/g)
	{
		my ($lang, $pid) = ($1, $2) ;
		push @audio_details, {'lang'=>lc $lang, 'pid'=>$pid} ;

print " + lang=$audio_details[-1]{lang}  pid=$audio_details[-1]{pid}\n" if $DEBUG >= 10 ;
	}

	# drop default audio
	shift @audio_details ;

	# process language spec
	if ($language_spec =~ s/\+//g)
	{
		# ensure default is in the list
		push @$pids_aref, $audio_pid ;

print " - lang spec contains '+', added default audio\n" if $DEBUG >= 10 ;
	}

print "process lang spec\n" if $DEBUG >= 10 ;

	# work through the language spec
	my $pid ;
	my $lang ;
	my @lang = split /[\s,]+/, $language_spec ;
	while (@lang)
	{
		$lang = shift @lang ;

print " + lang=$lang\n" if $DEBUG >= 10 ;
		
		$pid = undef ;
		while (!$pid && @audio_details)
		{
			my $audio_href = shift @audio_details ;
print " + + checking this audio detail: lang=$audio_href->{lang}  pid=$audio_href->{pid}\n" if $DEBUG >= 10 ;
			if ($audio_href->{'lang'} =~ /$lang/i)
			{
				$pid = $audio_href->{'pid'} ;
print " + + Found pid = $pid\n" if $DEBUG >= 10 ;

				push @$pids_aref, $pid ;
print " + Added pid = $pid\n" if $DEBUG >= 10 ;
			}
		}
		last unless @audio_details ;
	}
	
	# clean up
	if (@lang || !$pid)
	{
		unshift @lang, $lang if $lang ;
		$error = "Error: could not find the languages: " . join(', ', @lang) . " associated with program \"$demux_params_href->{pnr}\"" ;
	}
	
	return $error ;
}

#----------------------------------------------------------------------

=item B<out_pids($demux_params_href, $out_spec, $language_spec, $pids_aref)>

Process the demux parameters and an output specifier to return the list of all
stream pids required. 

Output specifier string is in the format such that it just needs to contain the following characters:

   a = audio
   v = video
   s = subtitle

Returns an array of HASHes of the form:

	 {'pid' => $pid, 'pidtype' => $type, 'pmt' => $pmt} 


=cut

sub out_pids
{
	my ($demux_params_href, $out_spec, $language_spec, $pids_aref) = @_ ;
	my $error = 0 ;

	## default
	$out_spec ||= "av" ;
	
#	my $pmt = $demux_params_href->{'pmt'} ;

	## Audio required?
	if ($out_spec =~ /a/i)
	{
		my @audio_pids ;
		$error = audio_pids($demux_params_href, $language_spec, \@audio_pids) ;
		return $error if $error ;
		
		foreach my $pid (@audio_pids)
		{
			push @$pids_aref, {
				'pid' => $pid, 
				'pidtype' => 'audio', 
					
				# keep ref to program HASH (used by downstream functions)  
				'demux_params'	=> $demux_params_href,
			} if $pid ;
		}
	}
	
	## Video required?
	if ($out_spec =~ /v/i)
	{
		my $pid = $demux_params_href->{'video'} ;
		push @$pids_aref, {
			'pid' => $pid, 
			'pidtype' => 'video', 
					
			# keep ref to program HASH (used by downstream functions)  
			'demux_params'	=> $demux_params_href,
		} if $pid ;
	}
	
	## Subtitle required?
	if ($out_spec =~ /s/i)
	{
		my $pid = $demux_params_href->{'subtitle'} ;
		push @$pids_aref, {
			'pid' => $pid, 
			'pidtype' => 'subtitle', 
					
			# keep ref to program HASH (used by downstream functions)  
			'demux_params'	=> $demux_params_href,
		} if $pid ;
	}
	
	return $error ;
}

#----------------------------------------------------------------------

=item B<audio_list($demux_params_href)>

Process the demux parameters and return a list of additional audio
streams (or an empty list if none available).

For example:

	        { 
	          audio => 601,                   
	          audio_details => eng:601 eng:602,       
				...
	        },

would return the list: ( 602 )


=cut

sub audio_list
{
	my ($demux_params_href) = @_ ;
	my @pids ;
	
	my $audio_pid = $demux_params_href->{'audio'} ;
	my $details = $demux_params_href->{'audio_details'} ;
	while ($details =~ m/(\S+):(\d+)/g)
	{
		my ($lang, $pid) = ($1, $2) ;
		push @pids, $pid if ($pid != $audio_pid) ;
	}
	
	return @pids ;
}


#----------------------------------------------------------------------

=item B<read($search_path)>

Read tuning information from config files. Look in search path and return first
set of readable file information in a tuning HASH ref.

Returns a HASH ref of tuning information - i.e. it contains the complete information on all
transponders (under the 'ts' field), and all programs (under the 'pr' field). [see L<Linux::DVB::DVBT::scan()> method for format].


=cut

sub read
{
	my ($search_path) = @_ ;
	
	$search_path = $DEFAULT_CONFIG_PATH unless defined($search_path) ;
	
	my $href ;
	my $dir = read_dir($search_path) ;
	if ($dir)
	{
		$href = {} ;
		foreach my $region (keys %FILES)
		{
		no strict "refs" ;
			my $fn = "read_dvb_$region" ;
			$href->{$region} = &$fn("$dir/$FILES{$region}") ;
		}
		
		print STDERR "Read config from $dir\n" if $DEBUG ;
		
	}
	return $href ;
}

#----------------------------------------------------------------------

=item B<write($search_path, $tuning_href)>

Write tuning information into the first writeable area in the search path.

=cut

sub write
{
	my ($search_path, $href) = @_ ;

	$search_path = $DEFAULT_CONFIG_PATH unless defined($search_path) ;
	my $dir = write_dir($search_path) ;
	if ($dir && $href)
	{
		foreach my $region (keys %FILES)
		{
		no strict "refs" ;
			my $fn = "write_dvb_$region" ;
			&$fn("$dir/$FILES{$region}", $href->{$region}) ;
		}

		print STDERR "Written config to $dir\n" if $DEBUG ;
	}
}


#----------------------------------------------------------------------

=item B<read_filename($filetype, [$search_path] )>

Returns the readable filename for the specified file type, which can be one of: 'pr'=program, 'ts'=transponder.

Optionally specify the search path (otherwise the default search path is used)

Returns undef if invalid file type is specified, or unable to find a readable area.

=cut

sub read_filename
{
	my ($filetype, $search_path) = @_ ;
	
	my $filename ;
	return $filename if (!exists($FILES{$filetype}));
	
	$search_path = $DEFAULT_CONFIG_PATH unless defined($search_path) ;
	my $dir = read_dir($search_path) ;

	if ($dir)
	{
		$filename = "$dir/$FILES{$filetype}" ;
	}
	return $filename ;
}

#----------------------------------------------------------------------

=item B<write_filename($filetype, [$search_path] )>

Returns the writeable filename for the specified file type, which can be one of: 'pr'=program, 'ts'=transponder.

Optionally specify the search path (otherwise the default search path is used)

Returns undef if invalid file type is specified, or unable to find a writeable area.

=cut

sub write_filename
{
	my ($filetype, $search_path) = @_ ;

	my $filename ;
	return $filename if (!exists($FILES{$filetype}));

	$search_path = $DEFAULT_CONFIG_PATH unless defined($search_path) ;
	my $dir = write_dir($search_path) ;

	if ($dir)
	{
		$filename = "$dir/$FILES{$filetype}" ;
	}
	return $filename ;
}





#----------------------------------------------------------------------

=item B<merge($new_href, $old_href)>

Merge tuning information - overwrites previous with new - into $old_href and return
the HASH ref.

=cut

sub merge
{
	my ($new_href, $old_href) = @_ ;

#	region: 'ts' => 
#		section: '4107' =>
#			field: name = Oxford/Bexley
#
	if ($old_href && $new_href)
	{
		foreach my $region (keys %FILES)
		{
			foreach my $section (keys %{$new_href->{$region}})
			{
				foreach my $field (keys %{$new_href->{$region}{$section}})
				{
					$old_href->{$region}{$section}{$field} = $new_href->{$region}{$section}{$field} ; 
				}
			}
		}
	}

	$old_href = $new_href if (!$old_href) ;
	
	return $old_href ;
}

#----------------------------------------------------------------------

=item B<merge_scan_freqs($new_href, $old_href, $verbose)>

Merge tuning information - checks to ensure new program info has the 
best strength, and that new program has all of it's settings

	'pr' =>
	      BBC ONE => 
	        {
	          pnr => 4171,
	          tsid => 4107,
	          tuned_freq => 57800000,
	          ...
	        },
	'ts' => 
	      4107 =>
	        { 
	          tsid => 4107,   
			  frequency => 57800000,            
	          ...
	        },
	'freqs' => 
	      57800000 =>
	        { 
	          strength => aaaa,               
	          snr => bbb,               
	          ber => ccc,               
	          ...
	        },



=cut

sub merge_scan_freqs
{
	my ($new_href, $old_href, $verbose) = @_ ;

print STDERR "merge_scan_freqs()\n" if $DEBUG ;

	if ($old_href && $new_href)
	{
		foreach my $region (keys %$new_href)
		{
			foreach my $section (keys %{$new_href->{$region}})
			{
				## merge programs/streams differently if they already exist
				my $overwrite = 1 ;
				if ( (($region eq 'pr')||($region eq 'ts')) && exists($old_href->{$region}{$section}) )
				{
print STDERR " + found 2 instances of {$region}{$section}\n" if $DEBUG ;
					# check for signal quality to compare
					my ($new_freq, $old_freq) ;
					foreach (qw/frequency tuned_freq/)
					{
						$new_freq = $new_href->{$region}{$section}{$_} if exists($new_href->{$region}{$section}{$_}) ;	
						$old_freq = $old_href->{$region}{$section}{$_} if exists($old_href->{$region}{$section}{$_}) ;	
					}
					if ($new_freq && $old_freq)
					{
						# just compare signal strength (for now!)
						my ($new_strength, $old_strength) ;
						foreach my $href ($new_href, $old_href)
						{
							$new_strength = $href->{'freqs'}{$new_freq}{'strength'} if exists($href->{'freqs'}{$new_freq}{'strength'} ) ;	
							$old_strength = $href->{'freqs'}{$old_freq}{'strength'} if exists($href->{'freqs'}{$old_freq}{'strength'} ) ;	
						}
						if ($new_strength && $old_strength)
						{
print STDERR " + checking $region $section  : Strength NEW=$new_strength  OLD=$old_strength\n" if $DEBUG ;
							if ($old_strength >= $new_strength)
							{
print STDERR " + + keep stronger signal (OLD)\n" if $DEBUG ;

								$new_strength = $new_strength * 100 / 65535 ;
								$old_strength = $old_strength * 100 / 65535 ;
								
								print STDERR "  Found 2 \"$section\" : keeping old signal $old_freq Hz $old_strength % (new $new_freq Hz $new_strength %)\n" if $verbose ;

								$overwrite = 0 ;
							}
						}
					}
				}
				
				if ($overwrite)
				{
print STDERR " + Overwrite existing {$region}{$section} with new ....\n" if $DEBUG ;
					## Just overwrite
					foreach my $field (keys %{$new_href->{$region}{$section}})
					{
						$old_href->{$region}{$section}{$field} = $new_href->{$region}{$section}{$field} ; 
					}
				}
			}
		}
	}

	$old_href = $new_href if (!$old_href) ;
	
print STDERR "merge_scan_freqs() - DONE\n" if $DEBUG ;
	
	return $old_href ;
}


#----------------------------------------------------------------------
# Split the search path & expand all the directories to absolute paths
#
sub _expand_search_path
{
	my ($search_path) = @_ ;

	my @dirs = split /:/, $search_path ;
	foreach my $d (@dirs)
	{
		# Replace any '~' with $HOME
		$d =~ s/~/\$HOME/g ;
		
		# Now replace any vars with values from the environment
		$d =~ s/\$(\w+)/$ENV{$1}/ge ;
		
		# Ensure path is clean
		$d = File::Spec->rel2abs($d) ;
	}
	
	return @dirs ;
}

#----------------------------------------------------------------------

=item B<read_dir($search_path)>

Find directory to read from - first readable directory in search path

=cut

sub read_dir
{
	my ($search_path) = @_ ;
	
	my @dirs = _expand_search_path($search_path) ;
	my $dir ;
	
	foreach my $d (@dirs)
	{
		my $found=1 ;
		foreach my $region (keys %FILES)
		{
			$found=0 if (! -f  "$d/$FILES{$region}") ;
		}
		
		if ($found)
		{
			$dir = $d ;
			last ;
		}
	}

	print STDERR "Searched $search_path : read dir=".($dir?$dir:"")."\n" if $DEBUG ;
		
	return $dir ;
}

#----------------------------------------------------------------------

=item B<write_dir($search_path)>

Find directory to write to - first writeable directory in search path

=cut

sub write_dir
{
	my ($search_path) = @_ ;

	my @dirs = _expand_search_path($search_path) ;
	my $dir ;

	print STDERR "Find dir to write to from $search_path ...\n" if $DEBUG ;
	
	foreach my $d (@dirs)
	{
		my $found=1 ;

		print STDERR " + processing $d\n" if $DEBUG ;

		# See if dir exists
		if (!-d $d)
		{
			# See if this user can create the dir
			eval {
				mkpath([$d], $DEBUG, 0755) ;
			};
			$found=0 if $@ ;

			print STDERR " + $d does not exist - attempt to mkdir=$found\n" if $DEBUG ;
		}		

		if (-d $d)
		{
			print STDERR " + $d does exist ...\n" if $DEBUG ;

			# See if this user can write to the dir
			foreach my $region (keys %FILES)
			{
				if (open my $fh, ">>$d/$FILES{$region}")
				{
					close $fh ;

					print STDERR " + + Write to $d/$FILES{$region} succeded\n" if $DEBUG ;
				}
				else
				{
					print STDERR " + + Unable to write to $d/$FILES{$region} - aborting this dir\n" if $DEBUG ;

					$found = 0;
					last ;
				}
			}
		}		
		
		if ($found)
		{
			$dir = $d ;
			last ;
		}
	}

	print STDERR "Searched $search_path : write dir=".($dir?$dir:"")."\n" if $DEBUG ;
	
	return $dir ;
}



#----------------------------------------------------------------------

=item B<read_dvb_ts($fname)>

Read the transponder settings file of the form:

	[4107]
	name = Oxford/Bexley
	frequency = 578000000
	bandwidth = 8
	modulation = 16
	hierarchy = 0
	code_rate_high = 34
	code_rate_low = 34
	guard_interval = 32
	transmission = 2
	
=cut

sub read_dvb_ts
{
	my ($fname) = @_ ;

	my %dvb_ts ;
	open my $fh, "<$fname" or die "Error: Unable to read $fname : $!" ;
	
	my $line ;
	my $tsid ;
	while(defined($line=<$fh>))
	{
		chomp $line ;
		next if $line =~ /^\s*#/ ; # skip comments
		 
		if ($line =~ /\[(\d+)\]/)
		{
			$tsid=$1;
		}
		elsif ($line =~ /(\S+)\s*=\s*(\S+)/)
		{
			if ($tsid)
			{
				$dvb_ts{$tsid}{$1} = $2 ;
			}
		}
		elsif ($line =~ /(\S+)\s*=/)
		{
			# skip empty entries
		}
		else
		{
			$tsid = undef ;
		}
	}	
	close $fh ;
	
	return \%dvb_ts ;
}

#----------------------------------------------------------------------

=item B<read_dvb_pr($fname)>

Read dvb-pr - channel information - of the form:
	
	[4107-4171]
	video = 600
	audio = 601
	audio_details = eng:601 eng:602
	type = 1
	net = BBC
	name = BBC ONE

=cut

sub read_dvb_pr
{
	my ($fname) = @_ ;

	my %dvb_pr ;
	open my $fh, "<$fname" or die "Error: Unable to read $fname : $!"  ;
	
	my $line ;
	my $pnr ;
	my $tsid ;
	while(defined($line=<$fh>))
	{
		chomp $line ;
		next if $line =~ /^\s*#/ ; # skip comments
		 
		if ($line =~ /\[([\d]+)\-([\d]+)\]/)
		{
			($tsid, $pnr)=($1,$2);
		}
		elsif ($line =~ /(\S+)\s*=\s*(\S+.*)/)
		{
			if ($pnr && $tsid)
			{
				$dvb_pr{"$tsid-$pnr"}{$1} = $2 ;
				
				# ensure tsid & pnr are in the hash
				$dvb_pr{"$tsid-$pnr"}{'tsid'} = $tsid ;
				$dvb_pr{"$tsid-$pnr"}{'pnr'} = $pnr ;
			}
		}
		elsif ($line =~ /(\S+)\s*=/)
		{
			# skip empty entries
		}
		else
		{
			$pnr = undef ;
			$tsid = undef ;
		}
	}	
	close $fh ;
	
	# Make channel name the first key
	my %chans ;
	foreach (keys %dvb_pr)
	{
		# handle chans with no name
		my $name = $dvb_pr{$_}{'name'} || $_ ; 
		$chans{$name} = $dvb_pr{$_} ; 
	}
	
	return \%chans ;
}


#----------------------------------------------------------------------

=item B<write_dvb_ts($fname, $href)>

Write transponder config information

=cut

sub write_dvb_ts
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	# Write config information
	#
	#	'ts' => 
	#	      4107 =>
	#	        { # HASH(0x83241b8)
	#	          bandwidth => 8,
	#	          code_rate_hp => 34,         code_rate_high
	#	          code_rate_lp => 34,         code_rate_low
	#	          constellation => 16,        modulation
	#	          frequency => 578000000,
	#	          guard => 32,                guard_interval
	#	          hierarchy => 0,
	#	          net => Oxford/Bexley,
	#	          transmission => 2,
	#	          tsid => 4107,               
	#	        },
	#	
	#[4107]
	#name = Oxford/Bexley
	#frequency = 578000000
	#bandwidth = 8
	#modulation = 16
	#hierarchy = 0
	#code_rate_high = 34
	#code_rate_low = 34
	#guard_interval = 32
	#transmission = 2
	#
	#
	foreach my $section (sort {$a <=> $b} keys %$href)
	{
		print $fh "[$section]\n" ;
		foreach my $field (sort keys %{$href->{$section}})
		{
			my $val = $href->{$section}{$field} ;
			if ($val =~ /\S+/)
			{
				print $fh "$field = $val\n" ;
			} 
		}
		print $fh "\n" ;
	}
	
	close $fh ;
}

#----------------------------------------------------------------------

=item B<write_dvb_pr($fname, $href)>

Write program config file.

=cut

sub write_dvb_pr
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	# Write config information
	#
	#	'pr' =>
	#	      BBC ONE => 
	#	        { # HASH(0x8327848)
	#	          a_pid => 601,                   audio
	#	          audio => eng:601 eng:602,       audio_details
	#	          ca => 0,
	#	          name => "BBC ONE",
	#	          net => BBC,
	#	          p_pid => 4171,                  -N/A-
	#	          pnr => 4171,
	#	          running => 4,
	#	          t_pid => 0,                     teletext
	#	          tsid => 4107,
	#	          type => 1,
	#	          v_pid => 600,                   video
	#	          version => 26,                  -N/A-
	#	        },
	#
	#[4107-4171]
	#video = 600
	#audio = 601
	#audio_details = eng:601 eng:602
	#type = 1
	#net = BBC
	#name = BBC ONE
	#
	foreach my $section (sort {
		$href->{$a}{'tsid'} <=> $href->{$b}{'tsid'}
		||
		$href->{$a}{'pnr'} <=> $href->{$b}{'pnr'}
	} keys %$href)
	{
		print $fh "[$href->{$section}{tsid}-$href->{$section}{pnr}]\n" ;
		foreach my $field (sort keys %{$href->{$section}})
		{
			my $val = $href->{$section}{$field} ;
			if ($val =~ /\S+/)
			{
				print $fh "$field = $val\n" ;
			} 
		}
		print $fh "\n" ;
	}
	
	close $fh ;
}


# ============================================================================================
# END OF PACKAGE
1;

