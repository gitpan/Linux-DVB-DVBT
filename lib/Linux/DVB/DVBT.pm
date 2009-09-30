package Linux::DVB::DVBT;

=head1 NAME

Linux::DVB::DVBT - Perl extension for DVB terrestrial recording, epg, and scanning 

=head1 SYNOPSIS

	use Linux::DVB::DVBT;
  
  	# get list of installed adapters
  	my @devices = Linux::DVB::DVBT->device_list() ;
  	foreach (@devices)
  	{
  		printf "%s : adapter number: %d, frontend number: %d\n", 
  			$_->{name}, $_->{adapter_num}, $_->{frontend_num} ;
  	}
  
	# Create a dvb object using the first dvb adapter in the list
	my $dvb = Linux::DVB::DVBT->new() ;
	
	# .. or specify the device numbers
	my $dvb = Linux::DVB::DVBT->new(
		'adapter_num' => 2,
		'frontend_num' => 1,
	) ;


	# Scan for channels
	$dvb->scan_from_file('/usr/share/dvb/dvb-t/uk-Oxford') ;
	
	# Set channel
	$dvb->select_channel("BBC ONE") ;
	
	# Get EPG data
	my ($epg_href, $dates_href) = $dvb->epg() ;

	# Record 30 minute program (after setting channel using select_channel method)
	$dvb->record('test.ts', 30*60) ;


=head1 DESCRIPTION

B<Linux::DVB::DVBT> is a package that provides an object interface to any installed Freeview 
tuner cards fitted to a Linux PC. The package supports initial set up (i.e. frequency scanning),
searching for the latest electronic program guide (EPG), and selectign a channel for recording
the video to disk.

Example scripts have been provided in the package which illustrate the expected use of the package (and
are useable programs in themeselves)

=over 4

=item dvbt-devices

Shows information about fited DVB-T tuners

=item dvbt-scan

Run this by providing the frequency file (usually stored in /usr/share/dvb/dvb-t). If run as root, this will set up the configuration
files for all users. For example:

   $ dvbt-scan /usr/share/dvb/dvb-t/uk-Oxford

NOTE: Frequency files are provided by the 'dvb' rpm package available for most distros

=item dvbt-epg

When run, this grabs the latest EPG information and updates a MySql database:

   $ dvbt-epg

=item dvbt-record

Specify the channel, the duration, and the output filename to record a channel:

   $ dvbt-record "bbc1" spooks.ts 1:00 
   
Note that the duration can be specified as an integer (number of minutes), or in HH:MM format (for hours and minutes)

=back

=head2 HISTORY

I started this package after being lent a Hauppauge WinTV-Nova-T usb tuner (thanks Tim!) and trying to 
do some command line recording. After I'd failed to get most applications to even talk to the tuner I discovered
xawtv (L<http://linux.bytesex.org/xawtv/>), started looking at it's source code and started reading the DVB-T standards.

This package is the result of various experminets and is being used for my web TV listing and program
record scheduling software.

=cut


#============================================================================================
# USES
#============================================================================================
use strict;
use warnings;
use Carp ;

use File::Basename ;
use File::Path ;
use POSIX qw(strftime);

#============================================================================================
# EXPORTER
#============================================================================================
require Exporter;
our @ISA = qw(Exporter);

#============================================================================================
# GLOBALS
#============================================================================================
our $VERSION = '1.03';
our $AUTOLOAD ;

#============================================================================================
# XS
#============================================================================================
require XSLoader;
XSLoader::load('Linux::DVB::DVBT', $VERSION);

#============================================================================================
# CLASS VARIABLES
#============================================================================================

my $DEBUG=0;
my $VERBOSE=0;
my $devices_aref ;

#============================================================================================

#my @CHANNEL_LIST = (
#  # TV
#  { 'channel' => "BBC ONE", 		'chan_num' => 1, },
#  { 'channel' => "BBC TWO", 		'chan_num' => 2, },
#  { 'channel' => "ITV1", 			'chan_num' => 3, },
#  { 'channel' => "Channel 4", 		'chan_num' => 4, },
#  { 'channel' => "Five", 			'chan_num' => 5, },
#  { 'channel' => "ITV2", 			'chan_num' => 6, },
#  { 'channel' => "BBC THREE", 		'chan_num' => 7, },
#  { 'channel' => "BBC FOUR", 		'chan_num' => 9, },
#  { 'channel' => "ITV3", 			'chan_num' => 10, },
#  { 'channel' => "SKY THREE", 		'chan_num' => 11, },
#  { 'channel' => "Yesterday",	 	'chan_num' => 12, },
#  { 'channel' => "Channel 4+1", 	'chan_num' => 13, },
#  { 'channel' => "More 4", 			'chan_num' => 14, },
#  { 'channel' => "QVC", 			'chan_num' => 16, },
#  { 'channel' => "G.O.L.D.", 		'chan_num' => 17, },
#  { 'channel' => "4Music",		 	'chan_num' => 18, },
#  { 'channel' => "Dave", 			'chan_num' => 19, },
#  { 'channel' => "Virgin1", 		'chan_num' => 20, },
#  { 'channel' => "TMF", 			'chan_num' => 21, },
#  { 'channel' => "Ideal World", 	'chan_num' => 22, },
#  { 'channel' => "Bid TV",		 	'chan_num' => 23, },
#  { 'channel' => "Dave ja vue", 	'chan_num' => 24, },
#  { 'channel' => "HOME",		 	'chan_num' => 26, },
#  { 'channel' => "ITV4", 			'chan_num' => 28, },
#  { 'channel' => "E4", 				'chan_num' => 29, },
#  { 'channel' => "E4+1", 			'chan_num' => 30, },
#  { 'channel' => "ITV2 +1", 		'chan_num' => 31, },
#  { 'channel' => "Film4", 			'chan_num' => 32, },
#  { 'channel' => "smile-TV2", 		'chan_num' => 33, },
#  { 'channel' => "ESPN", 			'chan_num' => 34, },
#  { 'channel' => "Five US", 		'chan_num' => 35, },
#  { 'channel' => "FIVER", 			'chan_num' => 36, },
#  { 'channel' => "smileTV", 		'chan_num' => 37, },
#  { 'channel' => "TOPUP Anytime1", 	'chan_num' => 38, },
#  { 'channel' => "TOPUP Anytime2", 	'chan_num' => 39, },
#  { 'channel' => "TOPUP Anytime3", 	'chan_num' => 40, },
#  { 'channel' => "TOPUP Anytime4", 	'chan_num' => 41, },
#  { 'channel' => "Gems TV", 		'chan_num' => 43, },
#  { 'channel' => "GEMSTV1", 		'chan_num' => 44, },
#  { 'channel' => "Lottery Xtra", 	'chan_num' => 45, },
#  { 'channel' => "smileTV2", 		'chan_num' => 46, },
#  { 'channel' => "QUEST", 			'chan_num' => 47, },
#  { 'channel' => "SuperCasino", 	'chan_num' => 48, },
#  { 'channel' => "Rocks & co", 		'chan_num' => 49, },
#  { 'channel' => "PARTYLAND", 		'chan_num' => 50, },
#  { 'channel' => "CBBC Channel", 	'chan_num' => 70, },
#  { 'channel' => "CBeebies", 		'chan_num' => 71, },
#  { 'channel' => "CITV", 			'chan_num' => 75, },
#  { 'channel' => "BBC NEWS", 		'chan_num' => 80, },
#  { 'channel' => "BBC Parliament", 	'chan_num' => 81, },
#  { 'channel' => "Sky News", 		'chan_num' => 82, },
#  { 'channel' => "Sky Spts News", 	'chan_num' => 83, },
#  { 'channel' => "CNN", 			'chan_num' => 83, },
#  { 'channel' => "Russia Today", 	'chan_num' => 83, },
#  { 'channel' => "Community", 		'chan_num' => 87, },
#  { 'channel' => "Teachers TV", 	'chan_num' => 88, },
#  { 'channel' => "Television X", 	'chan_num' => 97, },
#  { 'channel' => "Teletext", 		'chan_num' => 100, },
#  { 'channel' => "Ttext Holidays", 	'chan_num' => 101, },
#  { 'channel' => "Rabbit", 			'chan_num' => 102, },
#
#  # RADIO
#  { 'channel' => "BBC Radio 1", 	'chan_num' => 700, },
#  { 'channel' => "1Xtra BBC", 		'chan_num' => 701, },
#  { 'channel' => "BBC Radio 2", 	'chan_num' => 702, },
#  { 'channel' => "BBC Radio 3", 	'chan_num' => 703, },
#  { 'channel' => "BBC Radio 4", 	'chan_num' => 704, },
#  { 'channel' => "BBC R5L", 		'chan_num' => 705, },
#  { 'channel' => "BBC R5LSX", 		'chan_num' => 706, },
#  { 'channel' => "BBC 6 Music", 	'chan_num' => 707, },
#  { 'channel' => "BBC 7", 			'chan_num' => 708, },
#  { 'channel' => "BBC Asian Net.", 	'chan_num' => 709, },
#  { 'channel' => "BBC World Sv.", 	'chan_num' => 710, },
#  { 'channel' => "The Hits Radio", 	'chan_num' => 711, },
#  { 'channel' => "Smash Hits!", 	'chan_num' => 712, },
#  { 'channel' => "Kiss", 			'chan_num' => 713, },
#  { 'channel' => "heat", 			'chan_num' => 714, },
#  { 'channel' => "Magic", 			'chan_num' => 715, },
#  { 'channel' => "Q", 				'chan_num' => 716, },
#  { 'channel' => "SMOOTH RADIO", 	'chan_num' => 718, },
#  { 'channel' => "Kerrang!", 		'chan_num' => 722, },
#  { 'channel' => "talkSPORT", 		'chan_num' => 723, },
#  { 'channel' => "Premier Radio", 	'chan_num' => 725, },
#  { 'channel' => "Absolute Radio",	'chan_num' => 727, },
#  { 'channel' => "Heart", 			'chan_num' => 728, },
#) ;


=head2 FIELDS

All of the object fields are accessed via an accessor method of the same name as the field, or
by using the B<set> method where the field name and value are passed as key/value pairs in a HASH

=over 4

=item B<adapter_num> - DVB adapter number

Number of the DVBT adapter. When multiple DVBT adapters are fitted to a machine, they will be numbered from 0 onwards. Use this field to select the adapter.

=item B<frontend_num> - DVB frontend number

A single adapter may have multiple frontends. If so then use this field to select the frontend within the selected adapter.

=item B<frontend_name> - Device path for frontend (set multiplex)

Once the DVBT adapter has been selected, read this field to get the device path for the frontend. It will be of the form: /dev/dvb/adapter0/frontend0

=item B<demux_name> - Device path for demux (select channel within multiplex)

Once the DVBT adapter has been selected, read this field to get the device path for the demux. It will be of the form: /dev/dvb/adapter0/demux0

=item B<dvr_name> - Device path for dvr (video record access)

Once the DVBT adapter has been selected, read this field to get the device path for the dvr. It will be of the form: /dev/dvb/adapter0/dvr0

=item B<debug> - Set debug level

Set this to the required debug level. Higher values give more verbose information.

=item B<devices> - Fitted DVBT adapter list

Read this ARRAY ref to get the list of fitted DVBT adapters. This is equivalent to running the L</device_list()> class method (see L</device_list()> for array format)

=item B<channel_list> - Channel numbering 

Use this field to specify your preferred channel numbering.

You provide an ARRAY ref where the array contains HASHes of the form:

    {
        'channel' => <channel name>
        'channel_num' => <channel number>
    }

For example, you'd probably want 'BBC ONE' to have the channel number 1.

NOTE: When I've worked out how the logical channel numbering information is transmitted, then I'll automatically fill this in from the scan.

=item B<frontend_params> - Last used frontend settings 

This is a HASH ref containing the parameters used in the last call to L<set_frontend(%params)> (either externally or internally by this module).

=item B<config_path> - Search path for configuration files

Set to ':' separated list of directories. When the module wants to either read or write configuration settings (for channel frequencies etc) then it uses this field
to determine where to read/write those files from.

By default this is set to:

    /etc/dvb:~/.tv

Which means that the files are read from /etc/dvb if it has been created (by root); or alternatively it uses ~/.tv (which also happens to be where xawtv stores it's files). 
Similarly, when writing files these directories are searched until a writeable area is found (so a user won't be able to write into /etc/dvb).

=item B<tuning> - Channel tuning information

Use this field to read back the tuning parameters HASH ref as scanned or read from the configuration files (see L</scan()> method for format)

This field is only used internally by the object but can be used for debug/information.

=item B<errmode> - Set error handling mode

Set this field to either 'die' (the default) or 'return' and when an error occurs, the error mode action will be taken.

If the mode is set to 'die' then the application will terminate after printing all of the errors stored in the errors list (see L</errors> field).
When the mode is set to 'return' then the object method returns control back to the calling application with a non-zero status. It is the
application's responsibility to handle the errors (stored in  L</errors>)


=item B<errors> - List of errors

This is an ARRAY ref containing a list of any errors that have occurred. Each error is stored as a text string.

=back

=cut

# List of valid fields
my @FIELD_LIST = qw/dvb 
					adapter_num frontend_num
					frontend_name demux_name dvr_name
					debug 
					devices
					channel_list
					frontend_params
					config_path
					tuning
					errmode errors
					/ ;
my %FIELDS = map {$_=>1} @FIELD_LIST ;

# Default settings
my %DEFAULTS = (
	'adapter_num'	=> undef,
	'frontend_num'	=> 0,
	
	'frontend_name'	=> undef,
	'demux_name'	=> undef,
	'dvr_name'		=> undef,
	
	'dvb'			=> undef,
	
	# List of channels of the form:
	#
	# 'channel' => channel name
	# 'chan_num' => channel number
	#
##	'channel_list'	=> \@CHANNEL_LIST,
	'channel_list'	=> undef,

	# parameters used to tune the frontend
	'frontend_params' => undef,
	
	# Search path for config dir
	'config_path'	=> '/etc/dvb:~/.tv',

	# tuning info
	'tuning'		=> undef,
	
	# Information
	'devices'		=> [],
	
	# Error log
	'errors'		=> [],
	'errmode'		=> 'die',
) ;


#============================================================================================

=head2 CONSTRUCTOR

=over 4

=cut

#============================================================================================

=item C<< new([%args]) >>

Create a new object.

The %args are specified as they would be in the B<set> method, for example:

	'adapter_num' => 0

The full list of possible arguments are as described in the L</FIELDS> section

=cut

sub new
{
	my ($obj, %args) = @_ ;

	my $class = ref($obj) || $obj ;

	# Create object
	my $self = {} ;
	bless ($self, $class) ;

	# Initialise object
	$self->_init(%args) ;

	# Set devices list
	$self->device_list() ; # ensure list has been created
	$self->devices($devices_aref) ; # point to class ARRAY ref

	# Initialise hardware
	# Special case - allow for dvb being preset (for testing)
	unless($self->dvb)
	{
		$self->hwinit() ;
	}
	
	return($self) ;
}


#-----------------------------------------------------------------------------
# Object initialisation
sub _init
{
	my $self = shift ;
	my (%args) = @_ ;

	# Defaults
	foreach (@FIELD_LIST)
	{
		$self->{$_} = undef  ;
		$self->{$_} = $DEFAULTS{$_} if (exists($DEFAULTS{$_})) ;
	}

	# Set fields from parameters
	$self->set(%args) ;
}

#-----------------------------------------------------------------------------
# Object destruction
sub DESTROY
{
	my $self = shift ;

	if (ref($self->dvb()))
	{
		dvb_fini($self->dvb) ;
	}
}


#-----------------------------------------------------------------------------

=item C<< hwinit() >>

I<Object internal method>

Initialise the hardware (create dvb structure). Called once and sets the adpater &
frontend number for this object.

If no adapter number has been specified yet then use the first device in the list.

=cut

sub hwinit
{
	my $self = shift ;

	# If no adapter set, use first in list
	if (!defined($self->adapter_num))
	{
		# use first device found
		my $info_aref = $self->devices() ;
		if (scalar(@$info_aref))
		{
			$self->set(
				'adapter_num' => $info_aref->[0]{'adapter_num'},
				'frontend_num' => $info_aref->[0]{'frontend_num'},
			) ;
		}
		else
		{
			return $self->handle_error("Error: No adapters found to initialise") ;
		}
	}
	
	
	# Create DVB 
	my $dvb = dvb_init_nr($self->adapter_num, $self->frontend_num) ;
	$self->dvb($dvb) ;

	# get & set the device names
	my $names_href = dvb_device_names($dvb) ;
	$self->set(%$names_href) ;
}


#============================================================================================

=back

=head2 CLASS METHODS

Use as Linux::DVB::DVBT->method()

=over 4

=cut

#============================================================================================

#-----------------------------------------------------------------------------

=item C<< debug([$level]) >>

Set new debug level. Returns setting.

=cut

sub debug
{
	my ($obj, $level) = @_ ;

	if (defined($level))
	{
		$DEBUG = $level ;
	}

	return $DEBUG ;
}

#-----------------------------------------------------------------------------

=item C<< verbose([$level]) >>

Set new verbosity level. Returns setting.

=cut

sub verbose
{
	my ($obj, $level) = @_ ;

	if (defined($level))
	{
		$VERBOSE = $level ;
	}

	return $VERBOSE ;
}

#-----------------------------------------------------------------------------

=item C<< device_list() >>

Return list of available hardware as an array of hashes. Each hash entry is of the form:


    {
        'device'        => device name (e.g. '/dev/dvb/adapter0')
        'name'          => Manufacturer name
        'adpater_num'   => Adapter number
        'frontend_num'  => Frontend number
        'flags'         => Adapter capability flags
    }

Note that this information is also available via the object instance using the 'devices' method, but this
returns an ARRAY REF (rather than an ARRAY)

=cut

sub device_list
{
	my ($class) = @_ ;

	unless ($devices_aref)
	{
		# Get list of available devices & information for those devices
		$devices_aref = dvb_device() ;
	}
	
	return @$devices_aref ;
}


#============================================================================================

=back

=head2 OBJECT DATA METHODS

=over 4

=cut

#============================================================================================


#----------------------------------------------------------------------------

=item C<< set(%args) >>

Set one or more settable parameter.

The %args are specified as a hash, for example

	set('frequency' => 578000)

The full list of possible arguments are as described in the L</FIELDS> section

=cut

sub set
{
	my $self = shift ;
	my (%args) = @_ ;

	# Args
	foreach my $field (@FIELD_LIST)
	{
		if (exists($args{$field})) 
		{
			$self->$field($args{$field}) ;
		}
	}

}


#============================================================================================

=back

=head2 OBJECT METHODS

=over 4

=cut

#============================================================================================

#----------------------------------------------------------------------------

=item C<< select_channel($channel_name) >>

Tune the frontend & the demux based on $channel_name. 

This method uses a "fuzzy" search to match the specified channel name with the name broadcast by the network.
The case of the name is not important, and neither is whitespace. The search also checks for both numeric and
name instances of a number (e.g. "1" and "one").

For example, the following are all equivalent and match with the broadcast channel name "BBC ONE":

    bbc1
    BbC One
    b b c    1  

Returns 0 if ok; error code otherwise

=cut

sub select_channel
{
	my $self = shift ;
	my ($channel_name) = @_ ;

	# ensure we have the tuning info
	my $tuning_href = $self->get_tuning_info() ;
	if (! $tuning_href)
	{
		return $self->handle_error("Unable to get tuning information") ;
	}

	# get the channel info	
	my ($frontend_params_href, $demux_params_href) = Linux::DVB::DVBT::Config::find_channel($channel_name, $tuning_href) ;
	if (! $frontend_params_href)
	{
		return $self->handle_error("Unable to find channel $channel_name") ;
	}

	# Tune frontend
	if ($self->set_frontend(%$frontend_params_href))
	{
		return $self->handle_error("Unable to tune frontend") ;
	}

	# Set demux
	if ($self->set_demux($demux_params_href->{'video'}, $demux_params_href->{'audio'}, $demux_params_href->{'teletext'}))
	{
		return $self->handle_error("Unable to set demux") ;
	}

	return 0 ;
}
	

#----------------------------------------------------------------------------

=item C<< log_error($error_message) >>

I<Object internal method>

Add the error message to the error log. Get the log as an ARRAY ref via the 'errors()' method

=cut

sub log_error
{
	my $self = shift ;
	my ($error_message) = @_ ;
	
	push @{$self->errors()}, $error_message ;
	
}

#----------------------------------------------------------------------------

=item C<< handle_error($error_message) >>

Add the error message to the error log and then handle the error depending on the setting of the 'errmode' field. 

Get the log as an ARRAY ref via the 'errors()' method.

=cut

sub handle_error
{
	my $self = shift ;
	my ($error_message) = @_ ;

	# Log message
	$self->log_error($error_message) ;

	# Handle error	
	my $mode = $self->errmode ;
	
	if ($mode =~ m/return/i)
	{
		# return number of errors logged so far
		return scalar(@{$self->errors()}) ;
	}	
	elsif ($mode =~ m/die/i)
	{
		# Die showing all logged errors
		croak join ("\n", @{$self->errors()}) ;
	}	
}

#----------------------------------------------------------------------------

=item C<< set_frontend(%params) >>

Tune the frontend to the specified frequency etc. HASH %params contains:

    'frequency'
    'inversion'
    'bandwidth'
    'code_rate_high'
    'code_rate_low'
    'modulation'
    'transmission'
    'guard_interval'
    'hierarchy'
    'timeout'

(If you don't know what these parameters should be set to, then I recommend you just use the L<select_channel($channel_name)> method)

Returns 0 if ok; error code otherwise

=cut

sub set_frontend
{
	my $self = shift ;
	my (%params) = @_ ;

	# Set up the frontend
	my $rc = dvb_tune($self->{dvb}, {%params}) ;
	
	# If tuning went ok, then save params
	if ($rc == 0)
	{
		$self->frontend_params( {%params} ) ;
	}
	
	return $rc ;
}
	
#----------------------------------------------------------------------------

=item C<< set_demux($video_pid, $audio_pid, $teletext_pid) >>

Selects a particular video/audio stream (and optional teletext stream) and sets the
demultiplexer to those streams (ready for recording).

(If you don't know what these parameters should be set to, then I recommend you just use the L<select_channel($channel_name)> method)

Returns 0 for success; error code otherwise.

=cut

sub set_demux
{
	my $self = shift ;
	my ($video_pid, $audio_pid, $teletext_pid) = @_ ;

print "set_demux( <$video_pid>, <$audio_pid>, <$teletext_pid> )\n" if $DEBUG ;

	$teletext_pid ||= 0 ;

	return dvb_set_demux($self->{dvb}, $video_pid, $audio_pid, $teletext_pid) ;
}


#----------------------------------------------------------------------------

=item C<< epg() >>

Gathers the EPG information into a HASH using the previously tuned frontend and 
returns the EPG info. If the frontend is not yet tuned then the method attempts
to use the tuning information (either from a previous scan or from reading the config
files) to set up the frontend.

Note that you can safely run this method while recording; the EPG scan does not affect
the demux or the frontend (once it has been set)

Returns an array:

	[0] = EPG HASH
	[1] = Dates HASH

EPG HASH format is:

    $channel_name =>
       $pid => {
		'pid'		=> program unique id
		'channel'	=> channel name
		
		'date'		=> date
		'start'		=> start time
		'end'		=> end time
		'duration'	=> duration
		
		'title'		=> title string
		'text'		=> synopsis string
		'etext'		=> extra text (not usually used)
		'genre'		=> genre string
		
		'repeat'	=> repeat count
		'episode'	=> episode number
		'num_episodes' => number of episodes
	}

i.e. The information is keyed on channel name and program id (pid)

The genre string is formatted as:

    "Major category|genre/genre..."

For example:

    "Film|movie/drama (general)"

This allows for a simple regexp to extract the information (e.g. in a TV listings application 
you may want to only use the major category in the main view, then show the extra genre information in
a more detailed view)

Dates HASH format is:

    $channel_name => {
		'start_date'	=> date of first program for this channel 
		'start'			=> start time of first program for this channel
		
		'end_date'		=> date of last program for this channel 
		'end'			=> end time of last program for this channel
	}

i.e. The information is keyed on channel name

The dates HASH is created so that an existing EPG database can be updated by removing existing information for a channel between the indicated dates.

=cut


sub epg
{
	my $self = shift ;
	my ($section) = @_ ;		# debug only!
	
	$section ||= 0 ;

	my %epg ;
	my %dates ;

	# Get tuning information
	my $tuning_href = $self->get_tuning_info() ;

	## check for frontend tuned
	
	# if not tuned yet, attempt to auto-tune (assumes scan has been performed)
	if (!$self->frontend_params())
	{
		# Grab first channel settings & attempt to set frontend
		if ($tuning_href)
		{
			my $params_href = (values %{$tuning_href->{'ts'}})[0] ;
			$self->set_frontend(%$params_href) ;
		}
	}
			
	# if not tuned by now then we have to raise an error
	if (!$self->frontend_params())
	{
		# Raise an error
		return $self->handle_error("Frontend must be tuned before gathering EPG data (have you run scan() yet?)") ;
	}

	# Create a lookup table to convert [tsid-pnr] values into channel names & channel numbers 
	my $channel_lookup_href ;
	my $channels_aref = $self->get_channel_list() ;
	if ( $channels_aref && $tuning_href )
	{
#print "creating chan lookup\n" ;
#prt_data("Channels=", $channels_aref) ;
#prt_data("Tuning=", $tuning_href) ;
		$channel_lookup_href = {} ;
		foreach my $chan_href (@$channels_aref)
		{
			my $channel = $chan_href->{'channel'} ;

#print "CHAN: $channel\n" ;
			if (exists($tuning_href->{'pr'}{$channel}))
			{
#print "created CHAN: $channel for $tuning_href->{pr}{$channel}{tsid} -  for $tuning_href->{pr}{$channel}{pnr}\n" ;
				# create the lookup
				$channel_lookup_href->{"$tuning_href->{'pr'}{$channel}{tsid}-$tuning_href->{'pr'}{$channel}{pnr}"} = {
					'channel' => $channel,
					'chan_num' => $chan_href->{'chan_num'},
				} ;
			}
		}
	}	
#prt_data("Lookup=", $channel_lookup_href) ;

	# Gather EPG information into a list of HASH refs
	my $epg_data = dvb_epg($self->{dvb}, $VERBOSE, $DEBUG, $section) ;
prt_data("EPG data=", $epg_data) if $DEBUG ;
	
	# Analyse EPG info
	foreach my $epg_entry (@$epg_data)
	{
		my $tsid = $epg_entry->{'tsid'} ;
		my $pnr = $epg_entry->{'pnr'} ;

		my $chan = "$tsid-$pnr" ;		
		my $chan_num = $chan ;
		
		if ($channel_lookup_href)
		{
			# Replace channel name with the text name (rather than tsid/pnr numbers) 
			$chan_num = $channel_lookup_href->{$chan}{'chan_num'} || $chan ;
			$chan = $channel_lookup_href->{$chan}{'channel'} || $chan ;
		}
		
prt_data("EPG raw entry ($chan)=", $epg_entry) if $DEBUG ;
		
		# {chan}
		#	{pid}
		#              date => 18-09-2008,
		#              start => 23:15,
		#              end => 03:20,
		#              duration => 04:05,
		#
		#              title => Personal Services,
		#              text => This is a gently witty, if curiously coy, attempt by director
		#              genre => Film,
		#              
		#              episode => 1
		#			   num_episodes => 2
		#              repeat => 0
		#

		my @start_localtime =  localtime($epg_entry->{'start'}) ;
		my $start = strftime "%H:%M:%S", @start_localtime ;
		my $date  = strftime "%Y-%m-%d", @start_localtime ;

		my $pid_date = strftime "%Y%m%d", @start_localtime ;
		my $pid = "$epg_entry->{'id'}-$chan_num-$pid_date" ;	# id is reused on different channels 
		
		my @end_localtime =  localtime($epg_entry->{'stop'}) ;
		my $end = strftime "%H:%M:%S", @end_localtime ;
		my $end_date  = strftime "%Y-%m-%d", @end_localtime ;


		# keep track of dates
		$dates{$chan} ||= {
			'start_min'	=> $epg_entry->{'start'},
			'end_max'	=> $epg_entry->{'stop'},
			
			'start_date'	=> $date,
			'start'			=> $start,
			'end_date'		=> $end_date,
			'end'			=> $end,
		} ;

		if ($epg_entry->{'start'} < $dates{$chan}{'start_min'})
		{
			$dates{$chan}{'start_min'} = $epg_entry->{'start'} ;
			$dates{$chan}{'start_date'} = $date ;
			$dates{$chan}{'start'} = $start ;
		}
		if ($epg_entry->{'stop'} > $dates{$chan}{'end_max'})
		{
			$dates{$chan}{'end_max'} = $epg_entry->{'stop'} ;
			$dates{$chan}{'end_date'} = $end_date ;
			$dates{$chan}{'end'} = $end ;
		}


		my $duration = Linux::DVB::DVBT::Utils::duration($start, $end) ;
		
		my $title = Linux::DVB::DVBT::Utils::text($epg_entry->{'name'}) ;
		my $synopsis = Linux::DVB::DVBT::Utils::text($epg_entry->{'stext'}) ;
		my $etext = Linux::DVB::DVBT::Utils::text($epg_entry->{'etext'}) ;
		
		my $episode ;
		my $num_episodes ;
		my %flags ;
		
		Linux::DVB::DVBT::Utils::fix_title(\$title, \$synopsis) ;
		Linux::DVB::DVBT::Utils::fix_episodes(\$title, \$synopsis, \$episode, \$num_episodes) ;
		Linux::DVB::DVBT::Utils::fix_audio(\$title, \$synopsis, \%flags) ;
			

		$epg{$chan}{$pid} = {
			'pid'		=> $pid,
			'channel'	=> $chan,
			
			'date'		=> $date,
			'start'		=> $start,
			'end'		=> $end,
			'duration'	=> $duration,
			
			'title'		=> $title,
			'text'		=> $synopsis,
			'etext'		=> $etext,
			'genre'		=> $epg_entry->{'genre'},
			
			'repeat'	=> '',
			'episode'	=> $episode,
			'num_episodes' => $num_episodes,
		} ;

prt_data("EPG final entry ($chan) $pid=", $epg{$chan}{$pid}) if $DEBUG ;

	}
		
	return (\%epg, \%dates) ;
}






#----------------------------------------------------------------------------

=item C<< scan_from_file($freq_file) >>

Reads the DVBT frequency file (usually stored in /usr/share/dvb/dvb-t) and uses the contents to
set the frontend to the initial frequency. Then starts a channel scan using that tuning.

$freq_file must be the full path to the file. The file contents should be something like:

   # Oxford
   # T freq bw fec_hi fec_lo mod transmission-mode guard-interval hierarchy
   T 578000000 8MHz 2/3 NONE QAM64 2k 1/32 NONE

NOTE: Frequency files are provided by the 'dvb' rpm package available for most distros

Returns the discovered channel information as a HASH (see L</scan()>)

=cut

sub scan_from_file
{
	my $self = shift ;
	my ($freq_file) = @_ ;

	return $self->handle_error( "Error: No frequency file specified") unless $freq_file ;

	my %tuning_params ;

	# parse file
	open my $fh, "<$freq_file" or return $self->handle_error( "Error: Unable to read frequency file $freq_file : $!") ;
	my $line ;
	while (defined($line=<$fh>))
	{
		chomp $line ;
		if ($line =~ m%^\s*T\s+(\d+)\s+(\d+)MHz\s+(\d+)/(\d+)\s+(\w+)\s+QAM(\d+)\s+(\d+)k\s+(\d+)/(\d+)\s+(\w+)%i)
		{
			# get first
			my ($freq, $bw, $r_hi1, $r_hi2, $r_lo1, $r_lo2, $mo, $tr, $gu, $hi) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ;
			
			$tuning_params{'frequency'} = $freq if ($freq) ;
			$tuning_params{'bandwidth'} = $bw if ($bw) ;
			$tuning_params{'transmission'} = $tr if ($tr) ;
			$tuning_params{'guard_interval'} = $gu if ($gu) ;
			last ;
		}
	}
	close $fh ;
	
	return $self->handle_error( "Error: No tuning parameters found") unless keys %tuning_params ;
	
	# set tuning
	my $rc = $self->set_frontend(%tuning_params) ;
	return $self->handle_error( "Error: Tuning error : $rc" ) unless $rc==0 ;

	# Scan
	return $self->scan() ;
}


#----------------------------------------------------------------------------

=item C<< scan() >>

Starts a channel scan using previously set tuning. On successful completion of a scan,
saves the results into the configuration files.

Returns the discovered channel information as a HASH:

    'pr' => 
    { 
        $channel_name => 
        { 
          'audio' => "407",
          'audio_details' => "eng:407 und:408",
          'ca' => "0",
          'name' => "301",
          'net' => "BBC",
          'pnr' => "19456",
          'running' => "4",
          'teletext' => "0",
          'tsid' => "16384",
          'type' => "1",
          'video' => "203",
        },
		....
    },
    
    'ts' =>
    {
      $tsid => 
        { 
          'bandwidth' => "8",
          'code_rate_high' => "23",
          'code_rate_low' => "12",
          'frequency' => "713833330",
          'guard_interval' => "32",
          'hierarchy' => "0",
          'modulation' => "64",
          'net' => "Oxford/Bexley",
          'transmission' => "2",
        },
    	...
    }

Normally this information is only used internally.

=cut

sub scan
{
	my $self = shift ;

	# Get any existing info
	my $tuning_href = $self->get_tuning_info() ;

prt_data("Current tuning info=", $tuning_href) if $DEBUG ;

	# if not tuned by now then we have to raise an error
	if (!$self->frontend_params())
	{
		# Raise an error
		return $self->handle_error("Frontend must be tuned before running scan()") ;
	}


	# Do scan
	my $scan_href = dvb_scan($self->{dvb}, $VERBOSE) ;

prt_data("Scan results=", $scan_href) if $DEBUG ;

	# Merge results
	$scan_href = Linux::DVB::DVBT::Config::merge($scan_href, $tuning_href) ;

prt_data("Merged=", $scan_href) if $DEBUG ;

	# Save results
	$self->tuning($scan_href) ;
	Linux::DVB::DVBT::Config::write($self->config_path, $scan_href) ;

	return $self->tuning() ;
}

#----------------------------------------------------------------------------

=item C<< get_tuning_info() >>

I<Object internal method>

Check to see if 'tuning' information has been set. If not, attempts to read from the config
search path.

Returns a HASH ref of tuning information (see L</scan()> method for format); otherwise returns undef

=cut

sub get_tuning_info
{
	my $self = shift ;

	# Get any existing info
	my $tuning_href = $self->tuning() ;
	
	# If not found, try reading
	if (!$tuning_href)
	{
		$tuning_href = Linux::DVB::DVBT::Config::read($self->config_path) ;
		
		# save if got something
		$self->tuning($tuning_href) if $tuning_href ;
	}

	return $tuning_href ;
}

#----------------------------------------------------------------------------

=item C<< get_channel_list() >>

I<Object internal method>

Checks to see if 'channel_list' information has been set. If not, attempts to create a list based
on the scan information.

NOTE that the created list will be the best attempt at ordering the channels based on the TSID & PNR
which won't be pretty, but it'll be better than nothing!

Returns an ARRAY ref of channel_list information (see 'channel_list' field for format); otherwise returns undef

TODO: In a later release I'll work out how to use the logical channel number broadcast on the NIT

=cut

sub get_channel_list
{
	my $self = shift ;

	# Get any existing info
	my $channels_aref = $self->channel_list() ;
	
	# If not found, try creating
	if (!$channels_aref)
	{
#print "create chan list\n" ;

		# Get any existing info
		my $tuning_href = $self->get_tuning_info() ;
#prt_data("Tuning Info=",$tuning_href) ;
		
		# Use the scanning info to create an ordered list
		if ($tuning_href)
		{
			$channels_aref = [] ;
			$self->channel_list($channels_aref) ;
			
			my %tsid_pnr ;
			foreach my $channel_name (keys %{$tuning_href->{'pr'}})
			{
				$tsid_pnr{$tuning_href->{'pr'}{$channel_name}{'tsid'}}{$tuning_href->{'pr'}{$channel_name}{'pnr'}} = $channel_name ;
			}
#prt_data("TSID-PNR=",\%tsid_pnr) ;

			my $channel_num=1;
			foreach my $tsid (sort {$a <=> $b} keys %tsid_pnr)
			{
				foreach my $pnr (sort {$a <=> $b} keys %{$tsid_pnr{$tsid}})
				{
					push @$channels_aref, { 'channel'=>$tsid_pnr{$tsid}{$pnr}, 'channel_num'=>$channel_num++} ;
				}
			}
		}
#prt_data("Chans=",$channels_aref) ;
	}

	return $channels_aref ;
}



#----------------------------------------------------------------------------

=item C<< record($file, $duration) >>

Streams the selected channel information (see L</select_channel($channel_name)>) into the file $file for $duration.

The duration may be specified either as an integer number of minutes, or in HH:MM format (for hours & minutes), or in
HH:MM:SS format (for hours, minutes, seconds).

Note that (if possible) the method creates the directory path to the file if it doersn't already exist.

=cut

sub record
{
	my $self = shift ;
	my ($file, $duration) = @_ ;

	# Default to 30mins
	my $seconds = 30*60 ;
	
	# Convert duration to seconds
	if ($duration =~ m/^(\d+)$/)
	{
		$seconds = 60 * $1 ;
	}
	elsif ($duration =~ m/^(\d+):(\d+):(\d+)$/)
	{
		$seconds = (60*60 * $1) + (60 * $2) + $3 ;
	}
	elsif ($duration =~ m/^(\d+):(\d+)$/)
	{
		$seconds = (60*60 * $1) + (60 * $2) ;
	}

	# ensure directory is present
	my $dir = dirname($file) ;
	if (! -d $dir)
	{
		# create dir
		mkpath([$dir], $DEBUG, 0755) or return $self->handle_error("Unable to create record directory $dir : $!") ;
	}
	
	print "Recording to $file for $duration ($seconds secs)\n" if $DEBUG ;

	# save raw transport stream to file 
	my $rc = dvb_record($self->{dvb}, $file, $seconds) ;
	return $self->handle_error("Error during recording : $rc") if ($rc) ;
	
	return 0 ;
}




# ============================================================================================

sub AUTOLOAD 
{
    my $this = shift;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion
    my $class = $AUTOLOAD;
    $class =~ s/::[^:]+$//;  # get class

    my $type = ref($this) ;
    
	# possibly going to set a new value
	my $set=0;
	my $new_value = shift;
	$set = 1 if defined($new_value) ;
	
	# 1st see if this is of the form undef_<name>
	if ($name =~ m/^undef_(\w+)$/)
	{
		$set = 1 ;
		$name = $1 ;
		$new_value = undef ;
	}

	# check for valid field
	unless (exists($FIELDS{$name})) 
	{
		croak "Error: Attempting to access invalid field $name on $class";
	}

	# ok to get/set
	my $value = $this->{$name};

	if ($set)
	{
		$this->{$name} = $new_value ;
	}

	# Return previous value
	return $value ;
}


#=====================================================================
# MODULE USAGE
#=====================================================================
#

#---------------------------------------------------------------------
sub setup_modules
{
	# Attempt to load Debug object
	if (load_module('Debug::DumpObj'))
	{
		# Create local function
		*prt_data = sub {Debug::DumpObj::prt_data(@_)} ;
	}
	else
	{
		# See if we've got Data Dummper
		if (load_module('Data::Dumper'))
		{
			# Create local function
			*prt_data = sub {print Data::Dumper->Dump(@_)} ;
		}	
		else
		{
			# Create local function
			*prt_data = sub {print @_, "\n"} ;
		}
	}

}

#---------------------------------------------------------------------
sub load_module
{
	my ($mod) = @_ ;
	
	my $ok = 1 ;

	# see if we can load up the packages for thumbnail support
	if (eval "require $mod") 
	{
		$mod->import() ;
	}
	else 
	{
		# Can't load package
		$ok = 0 ;
	}
	return $ok ;
}

BEGIN {
	# Debug only
	setup_modules() ;
}



# ============================================================================================
# END OF PACKAGE

# ============================================================================================
# Utilities
# ============================================================================================
package Linux::DVB::DVBT::Utils ;

our %CONTENT_DESC = (
    0x10 => "Film|movie/drama (general)",
    0x11 => "Film|detective/thriller",
    0x12 => "Film|adventure/western/war",
    0x13 => "Film|science fiction/fantasy/horror",
    0x14 => "Film|comedy",
    0x15 => "Film|soap/melodrama/folkloric",
    0x16 => "Film|romance",
    0x17 => "Film|serious/classical/religious/historical movie/drama",
    0x18 => "Film|adult movie/drama",

    0x20 => "News|news/current affairs (general)",
    0x21 => "News|news/weather report",
    0x22 => "News|news magazine",
    0x23 => "News|documentary",
    0x24 => "News|discussion/interview/debate",

    0x30 => "Show|show/game show (general)",
    0x31 => "Show|game show/quiz/contest",
    0x32 => "Show|variety show",
    0x33 => "Show|talk show",

    0x40 => "Sports|sports (general)",
    0x41 => "Sports|special events (Olympic Games, World Cup etc.)",
    0x42 => "Sports|sports magazines",
    0x43 => "Sports|football/soccer",
    0x44 => "Sports|tennis/squash",
    0x45 => "Sports|team sports (excluding football)",
    0x46 => "Sports|athletics",
    0x47 => "Sports|motor sport",
    0x48 => "Sports|water sport",
    0x49 => "Sports|winter sports",
    0x4A => "Sports|equestrian",
    0x4B => "Sports|martial sports",

    0x50 => "Children|children's/youth programmes (general)",
    0x51 => "Children|pre-school children's programmes",
    0x52 => "Children|entertainment programmes for 6 to 14",
    0x53 => "Children|entertainment programmes for 10 to 16",
    0x54 => "Children|informational/educational/school programmes",
    0x55 => "Children|cartoons/puppets",

    0x60 => "Music|music/ballet/dance (general)",
    0x61 => "Music|rock/pop",
    0x62 => "Music|serious music/classical music",
    0x63 => "Music|folk/traditional music",
    0x64 => "Music|jazz",
    0x65 => "Music|musical/opera",
    0x66 => "Music|ballet",

    0x70 => "Arts|arts/culture (without music, general)",
    0x71 => "Arts|performing arts",
    0x72 => "Arts|fine arts",
    0x73 => "Arts|religion",
    0x74 => "Arts|popular culture/traditional arts",
    0x75 => "Arts|literature",
    0x76 => "Arts|film/cinema",
    0x77 => "Arts|experimental film/video",
    0x78 => "Arts|broadcasting/press",
    0x79 => "Arts|new media",
    0x7A => "Arts|arts/culture magazines",
    0x7B => "Arts|fashion",

    0x80 => "Social|social/political issues/economics (general)",
    0x81 => "Social|magazines/reports/documentary",
    0x82 => "Social|economics/social advisory",
    0x83 => "Social|remarkable people",

    0x90 => "Education|education/science/factual topics (general)",
    0x91 => "Education|nature/animals/environment",
    0x92 => "Education|technology/natural sciences",
    0x93 => "Education|medicine/physiology/psychology",
    0x94 => "Education|foreign countries/expeditions",
    0x95 => "Education|social/spiritual sciences",
    0x96 => "Education|further education",
    0x97 => "Education|languages",

    0xA0 => "Leisure|leisure hobbies (general)",
    0xA1 => "Leisure|tourism/travel",
    0xA2 => "Leisure|handicraft",
    0xA3 => "Leisure|motoring",
    0xA4 => "Leisure|fitness & health",
    0xA5 => "Leisure|cooking",
    0xA6 => "Leisure|advertizement/shopping",
    0xA7 => "Leisure|gardening",

    0xB0 => "Special|original language",
    0xB1 => "Special|black & white",
    0xB2 => "Special|unpublished",
    0xB3 => "Special|live broadcast",
);

our %AUDIO_FLAGS = (
  'AD' => 'is_audio_described',
  'S'  => 'is_subtitled',
  'SL' => 'is_deaf_signed',
);


#----------------------------------------------------------------------
# Convert text
#
#
sub text
{
	my ($text) = @_ ;

	if ($text)
	{
		$text =~ s/\\x([\da-fA-F]{2})/chr hex $1/ge ;
	}	
	return $text ;
}

#----------------------------------------------------------------------
# Convert category code into genre string
#
#
sub genre
{
	my ($cat) = @_ ;

	my $genre = "" ;
	if ($cat && exists($CONTENT_DESC{$cat}))
	{
		$genre = $CONTENT_DESC{$cat} ;
	}
		
	return $genre ;
}


#----------------------------------------------------------------------
sub fix_title
{
	my ($title_ref, $synopsis_ref) = @_ ;

	return unless ($$title_ref && $$synopsis_ref) ;

	# fix title when title is Julian Fellowes Investigates...
	# and synopsis is ...a Most Mysterious Murder. The Case of etc.
	if ($$synopsis_ref =~ s/^\.\.\. ?//) 
	{
		$$title_ref =~ s/\.\.\.//;
		$$synopsis_ref =~ s/^(.+?)\. //;
		if ($1) 
		{
			$$title_ref .= ' ' . $1;
			$$title_ref =~ s/ {2,}/ /;
		}
	}

	# Followed by ...
	$$synopsis_ref =~ s/Followed by .*// ;
	
}

#----------------------------------------------------------------------
sub fix_episodes
{
	my ($title_ref, $synopsis_ref, $episode_ref, $num_episodes_ref) = @_ ;

	# Series: "1/7"
	$$synopsis_ref ||= "" ;
	if ($$synopsis_ref =~ s%(\d+)/(\d+)[\:\.\s]+%%) 
	{
		$$episode_ref = $1;
		$$num_episodes_ref = $2;
	}
						
	# "Episode 1 of 7."
	if ($$synopsis_ref =~ s/\s*Episode (\d+) of (\d+)[\:\.\s]*//i) 
	{
		$$episode_ref = $1;
		$$num_episodes_ref = $2;
	}
						
}

#----------------------------------------------------------------------
sub fix_audio
{
	my ($title_ref, $synopsis_ref, $flags_href) = @_ ;

    # extract audio described / subtitled / deaf_signed from synopsis
	$$synopsis_ref ||= "" ;
	return unless $$synopsis_ref =~ s/\[([A-Z,]+)\][\.\s]*//;
	
	my $flags = $1;
    foreach my $flag (split ",", $flags) 
    {
	    my $method = $AUDIO_FLAGS{$flag} || next; # bad data
	    $flags_href->{$method} = 1;
    }
}



#---------------------------------------------------------------------------------------------------
# Convert time (in HH:MM format) into minutes
#
sub time2mins
{
#	my $this = shift ;

	my ($time) = @_ ;
	my $mins=0;
	if ($time =~ m/(\d+)\:(\d+)/)
	{
		$mins = 60*$1 + $2 ;
	}
	return $mins ;
}

#---------------------------------------------------------------------------------------------------
# Convert minutes into time (in HH:MM format)
#
sub mins2time
{
#	my $this = shift ;

	my ($mins) = @_ ;
	my $hours = int($mins/60) ;
	$mins = $mins % 60 ;
	my $time = sprintf "%02d:%02d", $hours, $mins ;
	return $time ;
}

#---------------------------------------------------------------------------------------------------
# Calculate duration in minutes between start and end times
#
sub duration
{
#	my $this = shift ;

	my ($start, $end) = @_ ;
	my $start_mins = time2mins($start) ;
	my $end_mins = time2mins($end) ;
	$end_mins += 24*60 if ($end_mins < $start_mins) ;
	my $duration_mins = $end_mins - $start_mins ;
	my $duration = mins2time($duration_mins) ;

#print "duration($start ($start_mins), $end ($end_mins)) = $duration ($duration_mins)\n" if $this->debug() ;

	return $duration ;
}

# ============================================================================================
# END OF PACKAGE

# ============================================================================================
# Config file
# ============================================================================================
package Linux::DVB::DVBT::Config ;

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

#----------------------------------------------------------------------
# Given a channel name, so a "fuzzy" search and return params if possible
#
sub find_channel
{
	my ($channel_name, $tuning_href) = @_ ;
	
	my ($frontend_params_href, $demux_params_href) ;

	## Look for channel info
	print "find $channel_name ...\n" if $DEBUG ;
	
	# start by just seeing if it's the correct name...
	if (exists($tuning_href->{'pr'}{$channel_name}))
	{
		$demux_params_href = $tuning_href->{'pr'}{$channel_name} ;
		print " + found $channel_name\n" if $DEBUG ;
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
print " -- $srch - replace $NUMERALS{$num} with $num..\n" if $DEBUG>3 ;
			$srch =~ s/($NUMERALS{$num})\b/$num/ge ;
print " -- -- $srch\n" if $DEBUG>3 ;
		}
		$srch =~ s/\s+//g ;
		$search{$srch}=1 ;

		print " + Searching tuning info [", keys %search, "]...\n" if $DEBUG>2 ;
		
		foreach my $chan (keys %{$tuning_href->{'pr'}})
		{
			my $srch_chan = lc $chan ;
			$srch_chan =~ s/\s+//g ;
			
			foreach my $search (keys %search)
			{
				print " + + checking $search against $srch_chan \n" if $DEBUG>2 ;
				if ($srch_chan eq $search)
				{
					$demux_params_href = $tuning_href->{'pr'}{$chan} ;
					print " + found $channel_name\n" if $DEBUG ;
					last ;
				}
			}
			
			last if $demux_params_href ;
		}
	}
	
	## If we've got the channel, look up it's frontend settings
	if ($demux_params_href)
	{
		my $tsid = $demux_params_href->{'tsid'} ;
		$frontend_params_href = $tuning_href->{'ts'}{$tsid} ;
	}

	return ($frontend_params_href, $demux_params_href) ;
}

#----------------------------------------------------------------------
# Read tuning information
#
#
sub read
{
	my ($search_path) = @_ ;
	
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
		
		print "Read config from $dir\n" if $DEBUG ;
		
	}
	return $href ;
}

#----------------------------------------------------------------------
# Write tuning information
#
#
sub write
{
	my ($search_path, $href) = @_ ;

	my $dir = write_dir($search_path) ;
	if ($dir && $href)
	{
		foreach my $region (keys %FILES)
		{
		no strict "refs" ;
			my $fn = "write_dvb_$region" ;
			&$fn("$dir/$FILES{$region}", $href->{$region}) ;
		}

		print "Written config to $dir\n" if $DEBUG ;
	}
}

#----------------------------------------------------------------------
# Merge tuning information
#
#	region: 'ts' => 
#		section: '4107' =>
#			field: name = Oxford/Bexley
#
sub merge
{
	my ($href1, $href2) = @_ ;

	if ($href2 && $href1)
	{
		foreach my $region (keys %FILES)
		{
			foreach my $section (keys %{$href2->{$region}})
			{
				foreach my $field (keys %{$href2->{$region}{$section}})
				{
					$href1->{$region}{$section}{$field} = $href2->{$region}{$section}{$field} ; 
				}
			}
		}
	}

	$href1 = $href2 if (!$href1) ;
	
	return $href1 ;
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
# Find directory to read from
#
#
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

	print "Searched $search_path : read dir=".($dir?$dir:"")."\n" if $DEBUG ;
		
	return $dir ;
}

#----------------------------------------------------------------------
# Find directory to write to
#
#
sub write_dir
{
	my ($search_path) = @_ ;

	my @dirs = _expand_search_path($search_path) ;
	my $dir ;

	print "Find dir to write to from $search_path ...\n" if $DEBUG ;
	
	foreach my $d (@dirs)
	{
		my $found=1 ;

		print " + processing $d\n" if $DEBUG ;

		# See if dir exists
		if (!-d $d)
		{
			# See if this user can create the dir
			eval {
				mkpath([$d], $DEBUG, 0755) ;
			};
			$found=0 if $@ ;

			print " + $d does not exist - attempt to mkdir=$found\n" if $DEBUG ;
		}		

		if (-d $d)
		{
			print " + $d does exist ...\n" if $DEBUG ;

			# See if this user can write to the dir
			foreach my $region (keys %FILES)
			{
				if (open my $fh, ">>$d/$FILES{$region}")
				{
					close $fh ;

					print " + + Write to $d/$FILES{$region} succeded\n" if $DEBUG ;
				}
				else
				{
					print " + + Unable to write to $d/$FILES{$region} - aborting this dir\n" if $DEBUG ;

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

	print "Searched $search_path : write dir=".($dir?$dir:"")."\n" if $DEBUG ;
	
	return $dir ;
}



#----------------------------------------------------------------------
# Read dvb-ts - station information
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
		else
		{
			$tsid = undef ;
		}
	}	
	close $fh ;
	
	return \%dvb_ts ;
}

#----------------------------------------------------------------------
# Read dvb-pr - channel information
#
#[4107-4171]
#video = 600
#audio = 601
#audio_details = eng:601 eng:602
#type = 1
#net = BBC
#name = BBC ONE
#
#
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
#	          tsid => 4107,               -N/A-
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
sub write_dvb_ts
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	foreach my $section (keys %$href)
	{
		print $fh "[$section]\n" ;
		foreach my $field (keys %{$href->{$section}})
		{
			print $fh "$field = $href->{$section}{$field}\n" ; 
		}
		print $fh "\n" ;
	}
	
	close $fh ;
}

#----------------------------------------------------------------------
# Write config information
#
#	'pr' =>
#	      BBC ONE => 
#	        { # HASH(0x8327848)
#	          a_pid => 601,                   audio
#	          audio => eng:601 eng:602,       audio_details
#	          ca => 0,
#	          name => BBC ONE,
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
sub write_dvb_pr
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	foreach my $section (keys %$href)
	{
		print $fh "[$href->{$section}{tsid}-$href->{$section}{pnr}]\n" ;
		foreach my $field (keys %{$href->{$section}})
		{
			print $fh "$field = $href->{$section}{$field}\n" ; 
		}
		print $fh "\n" ;
	}
	
	close $fh ;
}


# ============================================================================================
# END OF PACKAGE
1;

__END__

=back

=head1 ACKNOWLEDGEMENTS

Gerd Knorr for writing xawtv (see L<http://linux.bytesex.org/xawtv/>)

Some of the C code used in this module is used directly from Gerd's libng. All other files
are entirely written by me, or drastically modified from Gerd's original to (a) make the code
more 'Perl friendly', (b) to reduce the amount of code compiled into the library to just those
functions required by this module.  

=head1 AUTHOR

Steve Price

Please report bugs using L<http://rt.cpan.org>.

=head1 FUTURE

Subsequent releases will include:

=over 4

=item *

Support for event-driven applications (e.g. POE). I need to re-write some of the C to allow for event-driven hooks (and special select calls)

=item *

Extraction of channel numbering from broadcast. I want to work out how to decode the LCN.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Steve Price

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

