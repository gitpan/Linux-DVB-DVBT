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


	# show the logical channel numbers
	my $tuning_href = $dvb->get_tuning_info() ;
	my $channels_aref = $dvb->get_channel_list() ;
	
	print "Chans\n" ;
	foreach my $ch_href (@$channels_aref)
	{
		my $chan = $ch_href->{'channel'} ;
		printf "%3d : %-40s %5d-%5d $ch_href->{type}\n", 
			$ch_href->{'channel_num'},
			$chan,
			$tuning_href->{'pr'}{$chan}{'tsid'},
			$tuning_href->{'pr'}{$chan}{'pnr'} ;
	}

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

=item dvbt-ffrec

Similar to dvbt-record, but pipes the transport stream into ffmpeg and uses that to transcode the data directly into an MPEG file (without
saving the transport stream file).

Specify the channel, the duration, and the output filename to record a channel:

   $ dvbt-ffrec "bbc1" spooks.mpeg 1:00 
   
Note that the duration can be specified as an integer (number of minutes), or in HH:MM format (for hours and minutes)

=item dvbt-chans

Use to display the current list of tuned channels. Shows them in logical channel number order.

=back

=head2 Logical Channel Numbers (LCNs)

I've finally worked out how to gather the logical channel number information for all of the channels. The scan() method now stores the LCN information
into the config files, and makes the list of channels available through the L</get_channel_list()> method. So you can now get the channel number you
see (and enter) on any standard freeview TV or PVR.

This is of most interest if you want to use the L</epg()> method to gather data to create a TV guide. Generally, you'd like the channel listings
to be sorted in the order to which we've all become used to through TV viewing (i.e. it helps to have BBC1 appear before channel 4!). 


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
our $VERSION = '1.07';
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

=item B<merge> - Merge scan results 

Set this flag before running the scan() method. When set, the scan will merge the new results with any previous scan results (read from the config files)

By default this flag is set (so each scan merge with prvious results). Clear this flag to re-start from fresh - useful when broadcasters change the frequencies.

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

=item B<timeout> - Timeout

Set hardware timeout time in milliseconds. Most hardware will be ok using the default (900ms), but you can use this field to increase
the timeout time. 


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
					merge
					timeout
					
					_scan_freqs
					_device_index
					_device_info
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
	
	# merge scan results with existing
	'merge'			=> 1,
	
	# timeout period ms
	'timeout'		=> 900,
	
	######################################
	# Internal
	
	# scanning driven by frequency file
	'_scan_freqs'	=> 0,
	
	# which device in the device list are we
	'_device_index' => undef,
	
	# ref to this device's info from the device list
	'_device_info'	=> undef,
) ;

my $AUTO = 999 ;

#typedef enum fe_code_rate {
#	FEC_NONE = 0,
#	FEC_1_2,
#	FEC_2_3,
#	FEC_3_4,
#	FEC_4_5,
#	FEC_5_6,
#	FEC_6_7,
#	FEC_7_8,
#	FEC_8_9,
#	FEC_AUTO
#} fe_code_rate_t;
#
#    static char *ra_t[8] = {  ???
#	[ 0 ] = "12",
#	[ 1 ] = "23",
#	[ 2 ] = "34",
#	[ 3 ] = "56",
#	[ 4 ] = "78",
#    };
my %FE_CODE_RATE = (
	'NONE'		=> 0,
	'1/2'		=> 12,
	'2/3'		=> 23,
	'3/4'		=> 34,
	'4/5'		=> 45,
	'5/6'		=> 56,
	'6/7'		=> 67,
	'7/8'		=> 78,
	'8/9'		=> 89,
	'AUTO'		=> $AUTO,
) ;

#
#typedef enum fe_modulation {
#	QPSK,
#	QAM_16,
#	QAM_32,
#	QAM_64,
#	QAM_128,
#	QAM_256,
#	QAM_AUTO,
#	VSB_8,
#	VSB_16
#} fe_modulation_t;
#
#    static char *co_t[4] = {
#	[ 0 ] = "0",
#	[ 1 ] = "16",
#	[ 2 ] = "64",
#    };
#
my %FE_MOD = (
	'QPSK'		=> 0,
	'QAM16'		=> 16,
	'QAM32'		=> 32,
	'QAM64'		=> 64,
	'QAM128'	=> 128,
	'QAM256'	=> 256,
	'AUTO'		=> $AUTO,
) ;


#typedef enum fe_transmit_mode {
#	TRANSMISSION_MODE_2K,
#	TRANSMISSION_MODE_8K,
#	TRANSMISSION_MODE_AUTO
#} fe_transmit_mode_t;
#
#    static char *tr[2] = {
#	[ 0 ] = "2",
#	[ 1 ] = "8",
#    };
my %FE_TRANSMISSION = (
	'2k'		=> 2,
	'8k'		=> 8,
	'AUTO'		=> $AUTO,
) ;

#typedef enum fe_bandwidth {
#	BANDWIDTH_8_MHZ,
#	BANDWIDTH_7_MHZ,
#	BANDWIDTH_6_MHZ,
#	BANDWIDTH_AUTO
#} fe_bandwidth_t;
#
#    static char *bw[4] = {
#	[ 0 ] = "8",
#	[ 1 ] = "7",
#	[ 2 ] = "6",
#    };
my %FE_BW = (
	'8MHz'		=> 8,
	'7MHz'		=> 7,
	'6MHz'		=> 6,
	'AUTO'		=> $AUTO,
) ;

#
#typedef enum fe_guard_interval {
#	GUARD_INTERVAL_1_32,
#	GUARD_INTERVAL_1_16,
#	GUARD_INTERVAL_1_8,
#	GUARD_INTERVAL_1_4,
#	GUARD_INTERVAL_AUTO
#} fe_guard_interval_t;
#
#    static char *gu[4] = {
#	[ 0 ] = "32",
#	[ 1 ] = "16",
#	[ 2 ] = "8",
#	[ 3 ] = "4",
#    };
my %FE_GUARD = (
	'1/32'		=> 32,
	'1/16'		=> 16,
	'1/8'		=> 8,
	'1/4'		=> 4,
	'AUTO'		=> $AUTO,
) ;

#typedef enum fe_hierarchy {
#	HIERARCHY_NONE,
#	HIERARCHY_1,
#	HIERARCHY_2,
#	HIERARCHY_4,
#	HIERARCHY_AUTO
#} fe_hierarchy_t;
#
#    static char *hi[4] = {
#	[ 0 ] = "0",
#	[ 1 ] = "1",
#	[ 2 ] = "2",
#	[ 3 ] = "4",
#    };
#
my %FE_HIER = (
	'NONE'		=> 0,
	'1'			=> 1,
	'2'			=> 2,
	'4'			=> 4,
	'AUTO'		=> $AUTO,
) ;		

# =8 -> ?
#			$tuning_params{'bandwidth'} = $bw if ($bw) ;
# =2 -> AUTO
#			$tuning_params{'transmission'} = $tr if ($tr) ;
# =1 -> 1/16 ?
#			$tuning_params{'guard_interval'} = $gu if ($gu) ;

## All FE params
my %FE_PARAMS = (
	bandwidth 			=> \%FE_BW,
	code_rate_high 		=> \%FE_CODE_RATE,
	code_rate_low 		=> \%FE_CODE_RATE,
	modulation 			=> \%FE_MOD,
	transmission 		=> \%FE_TRANSMISSION,
	guard_interval 		=> \%FE_GUARD,
	hierarchy 			=> \%FE_HIER,
) ;

my %FE_CAPABLE = (
	bandwidth 			=> 'FE_CAN_BANDWIDTH_AUTO',
	code_rate_high 		=> 'FE_CAN_FEC_AUTO',
	code_rate_low 		=> 'FE_CAN_FEC_AUTO',
	modulation 			=> 'FE_CAN_QAM_AUTO',
	transmission 		=> 'FE_CAN_TRANSMISSION_MODE_AUTO',
	guard_interval 		=> 'FE_CAN_GUARD_INTERVAL_AUTO',
	hierarchy 			=> 'FE_CAN_HIERARCHY_AUTO',
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

	my $info_aref = $self->devices() ;

	# If no adapter set, use first in list
	if (!defined($self->adapter_num))
	{
		# use first device found
		if (scalar(@$info_aref))
		{
			$self->set(
				'adapter_num' => $info_aref->[0]{'adapter_num'},
				'frontend_num' => $info_aref->[0]{'frontend_num'},
			) ;
			$self->_device_index(0) ;
		}
		else
		{
			return $self->handle_error("Error: No adapters found to initialise") ;
		}
	}
	
	# If no frontend set, use first in list
	if (!defined($self->frontend_num))
	{
		# use first frontend found
		if (scalar(@$info_aref))
		{
			my $adapter = $self->adapter_num ;
			my $dev_idx=0;
			foreach my $device_href (@$info_aref)
			{
				if ($device_href->{'adapter_num'} == $adapter)
				{
					$self->frontend_num($device_href->{'frontend_num'}) ;				
					$self->_device_index($dev_idx) ;
					last ;
				}
				++$dev_idx ;
			}
		}
		else
		{
			return $self->handle_error("Error: No adapters found to initialise") ;
		}
	}
	
	## ensure device exists
	if (!defined($self->_device_index))
	{
		my $adapter = $self->adapter_num ;
		my $fe = $self->frontend_num ;
		my $dev_idx=0;
		foreach my $device_href (@$info_aref)
		{
			if ( ($device_href->{'adapter_num'} == $adapter) && ($device_href->{'frontend_num'} == $fe) )
			{
				$self->_device_index($dev_idx) ;
				last ;
			}
			++$dev_idx ;
		}
		if (!defined($self->_device_index))
		{
			return $self->handle_error("Error: Specified adapter ($adapter) and frontend ($fe) does not exist") ;
		}
	}
	
	## set info ref
	my $dev_idx = $self->_device_index() ;
	$self->_device_info($info_aref->[$dev_idx]) ;
	
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

=item C<< dvb_debug([$level]) >>

Set new debug level for dvb XS code

=cut

sub dvb_debug
{
	my ($obj, $level) = @_ ;

	dvb_set_debug($level||0) ;
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
	
	prt_data("DEVICE LIST=", $devices_aref) if $DEBUG >= 10 ;
	
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
	if ($self->set_frontend(%$frontend_params_href, 'timeout' => $self->timeout))
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

print STDERR "set_demux( <$video_pid>, <$audio_pid>, <$teletext_pid> )\n" if $DEBUG ;

	$teletext_pid ||= 0 ;

	return dvb_set_demux($self->{dvb}, $video_pid, $audio_pid, $teletext_pid, $self->{'timeout'}) ;
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

	# Create a lookup table to convert [tsid-pnr] values into channel names & channel numbers 
	my $channel_lookup_href ;
	my $channels_aref = $self->get_channel_list() ;
	if ( $channels_aref && $tuning_href )
	{
#print STDERR "creating chan lookup\n" ;
#prt_data("Channels=", $channels_aref) ;
#prt_data("Tuning=", $tuning_href) ;
		$channel_lookup_href = {} ;
		foreach my $chan_href (@$channels_aref)
		{
			my $channel = $chan_href->{'channel'} ;

#print STDERR "CHAN: $channel\n" ;
			if (exists($tuning_href->{'pr'}{$channel}))
			{
#print STDERR "created CHAN: $channel for $tuning_href->{pr}{$channel}{tsid} -  for $tuning_href->{pr}{$channel}{pnr}\n" ;
				# create the lookup
				$channel_lookup_href->{"$tuning_href->{'pr'}{$channel}{tsid}-$tuning_href->{'pr'}{$channel}{pnr}"} = {
					'channel' => $channel,
					'channel_num' => $tuning_href->{'pr'}{$channel}{'lcn'} || $chan_href->{'channel_num'},
				} ;
			}
		}
	}	
prt_data("Lookup=", $channel_lookup_href) if $DEBUG >= 2 ;


	## check for frontend tuned
	
	# list of carrier frequencies to tune to
	my @next_freq ;
	
	# if not tuned yet, tune to all station freqs (assumes scan has been performed)
	if (!$self->frontend_params())
	{
		# Grab first channel settings & attempt to set frontend
		if ($tuning_href)
		{
			@next_freq = values %{$tuning_href->{'ts'}} ;
			my $params_href = shift @next_freq ;
prt_data("Set frontend : params=", $params_href) if $DEBUG >= 2 ;
			$self->set_frontend(%$params_href, 'timeout' => $self->timeout) ;
		}
	}

	# start with a cleared list
	dvb_clear_epg() ;
	
	# collect all the EPG data from all carriers
	my $params_href ;
	my $epg_data ;
	do
	{		
		# if not tuned by now then we have to raise an error
		if (!$self->frontend_params())
		{
			# Raise an error
			return $self->handle_error("Frontend must be tuned before gathering EPG data (have you run scan() yet?)") ;
		}
	
		# Gather EPG information into a list of HASH refs (collects all previous runs)
		$epg_data = dvb_epg($self->{dvb}, $VERBOSE, $DEBUG, $section) ;

		# tune to next carrier in the list (if any are left)
		$params_href = undef ;
		if (@next_freq)
		{
			$params_href = shift @next_freq ;
prt_data("Retune params=", $params_href)  if $DEBUG >= 2 ;
			$self->set_frontend(%$params_href, 'timeout' => $self->timeout) ;
		}
	}
	while ($params_href) ;

prt_data("EPG data=", $epg_data) if $DEBUG ;

	# ok to clear down the low-level list now
	dvb_clear_epg() ;
		
	# Analyse EPG info
	foreach my $epg_entry (@$epg_data)
	{
		my $tsid = $epg_entry->{'tsid'} ;
		my $pnr = $epg_entry->{'pnr'} ;

		my $chan = "$tsid-$pnr" ;		
		my $channel_num = $chan ;
		
		if ($channel_lookup_href)
		{
			# Replace channel name with the text name (rather than tsid/pnr numbers) 
			$channel_num = $channel_lookup_href->{$chan}{'channel_num'} || $chan ;
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
		my $pid = "$epg_entry->{'id'}-$channel_num-$pid_date" ;	# id is reused on different channels 
		
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

# TODOs
#
# 1. Pass freq info back up here
# 2. Don't re-scan previously seen freqs
# 3. Use prog TSID + prog freq to determine Transponders
#
sub scan_from_file
{
	my $self = shift ;
	my ($freq_file) = @_ ;

	return $self->handle_error( "Error: No frequency file specified") unless $freq_file ;

	print STDERR "scan_from_file() : Linux::DVB::DVBT version $VERSION\n\n" if $DEBUG ;

	my @tuning_list ;

	# device info
	my $dev_info_href = $self->_device_info ;
	my $capabilities_href = $dev_info_href->{'capabilities'} ;

prt_data("Capabilities=", $capabilities_href, "FE Cap=", \%FE_CAPABLE)  if $DEBUG>=2 ;


	## parse file
	open my $fh, "<$freq_file" or return $self->handle_error( "Error: Unable to read frequency file $freq_file : $!") ;
	my $line ;
	while (defined($line=<$fh>))
	{
		chomp $line ;
		## # T freq      bw   fec_hi fec_lo mod   transmission-mode guard-interval hierarchy
		##   T 578000000 8MHz 2/3    NONE   QAM64 2k                1/32           NONE

		if ($line =~ m%^\s*T\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)%i)
		{
			my $freq = $1 ;

			## setting all params doesn't necessarily work since the freq file is quite often out of date!				
			my %params = (
				bandwidth => $2,
				code_rate_high => $3,
				code_rate_low => $4,
				modulation => $5,
				transmission => $6,
				guard_interval => $7,
				hierarchy => $8,
			) ;
			
			# convert file entry into a frontend param
			my %tuning_params ;
			foreach my $param (keys %params)
			{
				## convert freq file value into VDR format
				if (exists($FE_PARAMS{$param}{$params{$param}}))
				{
					$tuning_params{$param} = $FE_PARAMS{$param}{$params{$param}} ;
				}				
			}
			$tuning_params{'frequency'} = $freq ;

prt_data("Tuning params=", \%tuning_params) if $DEBUG>=2 ;

			## add to tuning list
			push @tuning_list, \%tuning_params ;
		}
	}
	close $fh ;
	
	# exit on failure
	return $self->handle_error( "Error: No tuning parameters found") unless @tuning_list ;

	## prep for scan
	dvb_scan_new($self->{dvb}, $VERBOSE) ;

	## tune into each frequency & perform the scan
	my $freqs_href = {} ;
	my $saved_merge = $self->merge ;
	while (@tuning_list)
	{
		my $tuned = 0 ;

print STDERR "Loop start: ".scalar(@tuning_list)." freqs\n" if $DEBUG>=2 ;
		
		while (!$tuned)
		{
			my $tuning_params_href = shift @tuning_list ;

			# convert file entry into a frontend param
			my %tuning_params ;
			foreach my $param (keys %$tuning_params_href)
			{
				next unless exists($FE_CAPABLE{$param}) ;
print STDERR " +check param $param\n" if $DEBUG>=2 ;

				## check to see if we are capable of using auto
				unless ($capabilities_href->{$FE_CAPABLE{$param}})
				{
					# can't use auto so we have to set it
					$tuning_params{$param} = $tuning_params_href->{$param} ;
				}
			}
			$tuning_params{'frequency'} = $tuning_params_href->{'frequency'} ;
			
			# set tuning
			print STDERR "Setting frequency: $tuning_params{frequency} Hz\n" if $self->verbose ;
#			my $rc = $self->set_frontend(%tuning_params, 'timeout' => $self->timeout) ;
			my $rc = dvb_scan_tune($self->{dvb}, {%tuning_params}) ;
			
			# If tuning went ok, then save params
			if ($rc == 0)
			{
				$self->frontend_params( {%tuning_params} ) ;
				$tuned = 1 ;
			}
			else
			{
				print STDERR "    Failed to set the DVB-T tuner to $tuning_params{frequency} Hz ... skipping\n" ;

				# try next frequency
				last unless @tuning_list ;			
			}

print STDERR "Attempt tune: ".scalar(@tuning_list)." freqs\n" if $DEBUG>=2 ;

		}
		
		last if !$tuned ;
	
		# Scan
		$self->_scan_freqs(1) ;
		$self->scan() ;
		$self->_scan_freqs(0) ;
		
		# ensure next results are merged in
		$self->merge(1) ;
		
		# update frequency list
		my $tuning_href = $self->tuning ;
		$freqs_href = $tuning_href->{'freqs'} if exists($tuning_href->{'freqs'}) ;
		
		# update frequencies
		my %freq_list ;
		foreach my $href (@tuning_list)
		{
			$freq_list{$href->{'frequency'}} = 1 ;
		}
		foreach my $freq (keys %$freqs_href)
		{
			next if $freqs_href->{$freq}{'seen'} ;
			if (!exists($freq_list{$freq}) )
			{
				push @tuning_list, {
					'frequency'		=> $freq,
					%{$freqs_href->{$freq}},
				} ;
print STDERR " + adding freq $freq\n" if $DEBUG>=2 ;
			}
		} 

prt_data("Loop end Tuning list=", \@tuning_list) if $DEBUG>=2 ;

print STDERR "Loop end: ".scalar(@tuning_list)." freqs\n" if $DEBUG>=2 ;

	}

	## restore flag
	$self->merge($saved_merge) ;

	## clear ready for next scan
	dvb_scan_new($self->{dvb}, $VERBOSE) ;


	## return tuning settings	
	return $self->tuning() ;
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
          'lcn' => 301
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

prt_data("Current tuning info=", $tuning_href) if $DEBUG>=5 ;

	# if not tuned by now then we have to raise an error
	if (!$self->frontend_params())
	{
		# Raise an error
		return $self->handle_error("Frontend must be tuned before running scan()") ;
	}

	## Initialise for scan
	dvb_scan_new($self->{dvb}, $VERBOSE) unless $self->_scan_freqs ;
	dvb_scan_init($self->{dvb}, $VERBOSE) ;


	## Do scan
	#
	#	Scan results are returned in arrays:
	#	
	#  freqs => 
	#    { # HASH(0x844d76c)
	#      482000000 => 
	#        { # HASH(0x8448da4)
	#          'seen' => 1,
	#          'strength' => 0,
	#          'tuned' => 0,
	#        },
	#	
	#    'pr' => 
	#    [ 
	#        { 
	#          'audio' => "407",
	#          'audio_details' => "eng:407 und:408",
	#          'ca' => "0",
	#          'name' => "301",
	#          'net' => "BBC",
	#          'pnr' => "19456",
	#          'running' => "4",
	#          'teletext' => "0",
	#          'tsid' => "16384",
	#          'type' => "1",
	#          'video' => "203",
	#          'lcn' => 301
	#          'freqs' => [
	#				57800000,
	#			],
	#        },
	#		....
	#    ],
	#    
	#    'ts' =>
	#    [
	#        { 
	#          'tsid' => 4107,
	#          'bandwidth' => "8",
	#          'code_rate_high' => "23",
	#          'code_rate_low' => "12",
	#          'frequency' => "713833330",	# reported centre freq
	#          'guard_interval' => "32",
	#          'hierarchy' => "0",
	#          'modulation' => "64",
	#          'net' => "Oxford/Bexley",
	#          'transmission' => "2",
	#		   'lcn' =>
	#		   {
	#		   		$pnr => {
	#		   			'lcn' => 305,
	#		   			'service_type' => 24,
	#		   			'visible' => 1,
	#		   		}
	#		   }
	#        },
	#    	...
	#    ]
	#
	# these results need to analysed and converted into the expected format:
	#
	#    'pr' => 
	#    { 
	#        $channel_name => 
	#        { 
	#          'audio' => "407",
	#			...
	#        },
	#		....
	#    },
	#    
	#    'ts' =>
	#    {
	#      $tsid => 
	#        { 
	#          'bandwidth' => "8",
	#			...
	#        },
	#    	...
	#    }
	#
	# 
	my $raw_scan_href = dvb_scan($self->{dvb}, $VERBOSE) ;

prt_data("Raw scan results=", $raw_scan_href) if $DEBUG>=5 ;
print STDERR "dvb_scan_end()...\n" if $DEBUG>=5 ;

	## Clear up after scan
	dvb_scan_end($self->{dvb}, $VERBOSE) ;
	dvb_scan_new($self->{dvb}, $VERBOSE) unless $self->_scan_freqs ;

print STDERR "process raw...\n" if $DEBUG>=5 ;

	## Process the raw results for programs
	my $scan_href = {
		'freqs' => $raw_scan_href->{'freqs'},
		'lcn' 	=> {},
	} ;

	# create hash of frequencies/channel names for the programs
	my %programs ;
	foreach my $prog_href (@{$raw_scan_href->{'pr'}})
	{
		my $chan = $prog_href->{'name'} ;
		
		# create a program entry for each frequency
		my $freqs_aref = delete $prog_href->{'freqs'} ;
		foreach my $freq (@$freqs_aref)
		{
			$programs{$freq}{$chan} = $prog_href ;
		}
	}
prt_data("Programs=", \%programs) if $DEBUG>=5 ;

	# process each freq/channel
	my %tsids ;
	foreach my $freq (keys %programs)
	{
		# process progs
		foreach my $chan (keys %{$programs{$freq}})
		{
			# map tsid to freq(s)
			my $tsid = $programs{$freq}{$chan}{'tsid'} ;
			$tsids{$tsid}{$freq} = 1 ;
			
			## add to processed hash 

			# see if there are more than 1
			my $overwrite = 1 ;
			$scan_href->{'pr'} ||= {} ;
			if (exists($scan_href->{'pr'}{$chan}))
			{	
				my $existing_freq = $scan_href->{'pr'}{$chan}{'tuned_freq'} ;

print STDERR " + found 2 progs \"$chan\" : existing $existing_freq Hz ($raw_scan_href->{'freqs'}{$existing_freq}{'strength'}) -> new $freq Hz ($raw_scan_href->{'freqs'}{$freq}{'strength'})\n" if $DEBUG>=5 ;
				
				# use channel associated with strongest transponder
				$overwrite=0;
				if ($raw_scan_href->{'freqs'}{$freq}{'strength'} > $raw_scan_href->{'freqs'}{$existing_freq}{'strength'})
				{
					my $new_strength = $raw_scan_href->{'freqs'}{$freq}{'strength'} * 100 / 65535 ;
					my $old_strength = $raw_scan_href->{'freqs'}{$existing_freq}{'strength'} * 100 / 65535 ;
					
					print STDERR "  Found 2 programs \"$chan\" : using new signal $new_strength % (old $old_strength %)\n" if $VERBOSE ;
					
					$overwrite = 1 ;
print STDERR " + + using new\n" if $DEBUG>=5 ;
				}
			}
			if ($overwrite)
			{		
				$scan_href->{'pr'}{$chan} = $programs{$freq}{$chan} ;
			}
		}
	}
prt_data("TSIDs=", \%tsids) if $DEBUG>=5 ;
print STDERR "process raw streams...\n" if $DEBUG>=5 ;
	
	## Process the results for transponders
	my %transponders ;
	foreach my $stream_href (@{$raw_scan_href->{'ts'}})
	{
		# map tsid+freq to a transponder
		my $tsid = $stream_href->{'tsid'} ;
		my $centre_freq = $stream_href->{'frequency'} ;
		$transponders{"$centre_freq-$tsid"} = $stream_href ;
	}

prt_data("Transponders=", \%transponders) if $DEBUG>=5 ;
print STDERR "process tsids...\n" if $DEBUG>=5 ;

	foreach my $tsid (keys %tsids)
	{
		my @freqs = keys %{$tsids{$tsid}} ;
		my $freq = $freqs[0] ;
		
		# see if we have more than one
		if (@freqs > 1)
		{
print STDERR " + found more than 1 transponder providing $tsid\n" if $DEBUG>=5 ;
			# use best signal
			foreach my $f2 (@freqs)
			{
				next unless $freq == $f2 ;

				my $new_strength = $raw_scan_href->{'freqs'}{$freq}{'strength'} * 100 / 65535 ;
				my $old_strength = $raw_scan_href->{'freqs'}{$f2}{'strength'} * 100 / 65535 ;
				
				print STDERR "  Found 2 transponders TSID $tsid : using new signal $new_strength % (old $old_strength %)\n" if $VERBOSE ;

print STDERR " + + compare $freq Hz ($raw_scan_href->{'freqs'}{$freq}{'strength'}) -> $f2 Hz ($raw_scan_href->{'freqs'}{$f2}{'strength'})\n" ;
				if ($raw_scan_href->{'freqs'}{$f2}{'strength'} > $raw_scan_href->{'freqs'}{$freq}{'strength'})
				{
					$freq = $f2 ;
				}
			}
		}
print STDERR " + tsid $tsid => $freq Hz\n" if $DEBUG>=5 ;
		
		# keep best transponder iff it is valid
		if (exists($transponders{"$freq-$tsid"}))
		{
			# get the transponder info
			$scan_href->{'ts'}{$tsid} = $transponders{"$freq-$tsid"} ;
			
			# move this transponder's lcn info into lcn hash
			if (exists($scan_href->{'ts'}{$tsid}{'lcn'}))
			{
				my $lcn_href = delete $scan_href->{'ts'}{$tsid}{'lcn'} ;
				$scan_href->{'lcn'}{$tsid} = $lcn_href ;
			}
			
			# add signal strength
			$scan_href->{'ts'}{$tsid}{'strength'} = $raw_scan_href->{'freqs'}{$freq}{'strength'} ;
		}
	}
	
prt_data("Scan results=", $scan_href) if $DEBUG>=5 ;
print STDERR "process rest...\n" if $DEBUG>=5 ;
	
	## Post-process to weed out undesirables!
	my %tsid_map ;
	my @del ;
	foreach my $chan (keys %{$scan_href->{'pr'}})
	{
		if ($chan !~ /\S+/)
		{
			push @del, $chan ;
			next ;
		}
		my $tsid = $scan_href->{'pr'}{$chan}{'tsid'} ;
		my $pnr = $scan_href->{'pr'}{$chan}{'pnr'} ;
		$tsid_map{"$tsid-$pnr"} = $chan ;
	}
	
	foreach my $chan (@del)
	{
print STDERR " + del chan \"$chan\"\n" if $DEBUG>=5 ;

		delete $scan_href->{'pr'}{$chan} ;
	}

prt_data("!!POST-PROCESS tsid_map=", \%tsid_map) if $DEBUG>=5 ;
	
	## Post-process based on logical channel number iff we have this data
	
	#  lcn =>
	#    { # HASH(0x83d2608)
	#      12290 =>
	#        { # HASH(0x8442524)
	#          12866 =>
	#            { # HASH(0x8442578)
	#              service_type => 2,
	#            },
	#        },
	#      16384 =>
	#        { # HASH(0x8442af4)
	#          18496 =>
	#            { # HASH(0x8442b48)
	#              lcn => 700,
	#              service_type => 4,
	#              visible => 1,
	#            },
	#        },
	if (keys %{$scan_href->{'lcn'}})
	{
		foreach my $tsid (keys %{$scan_href->{'lcn'}})
		{
			foreach my $pnr (keys %{$scan_href->{'lcn'}{$tsid}})
			{
				my $lcn_href = $scan_href->{'lcn'}{$tsid}{$pnr} ;
				my $chan = $tsid_map{"$tsid-$pnr"} ;
	
				next unless $chan ;
				next unless exists($scan_href->{'pr'}{$chan}) ;
	
	if ($DEBUG>=5)
	{
		my $lcn = defined($lcn_href->{'lcn'}) ? $lcn_href->{'lcn'} : 'undef' ;
		my $vis = defined($lcn_href->{'visible'}) ? $lcn_href->{'visible'} : 'undef' ;
		my $type = defined($lcn_href->{'service_type'}) ? $lcn_href->{'service_type'} : 'undef' ;
		 
	print STDERR " : $tsid-$pnr - $chan : lcn=$lcn, vis=$vis, service type=$type type=$scan_href->{'pr'}{$chan}{'type'}\n" ;
	}	
			
				## handle LCN if set
				my $delete = 0 ;
				if ($lcn_href && $lcn_href->{'lcn'} )
				{
					## Set entry channel number
					$scan_href->{'pr'}{$chan}{'lcn'} = $lcn_href->{'lcn'} ;
	
	print STDERR " : : set lcn for $chan : vid=$scan_href->{'pr'}{$chan}{'video'}  aud=$scan_href->{'pr'}{$chan}{'audio'}\n" if $DEBUG>=5 ;
	
					if (!$lcn_href->{'visible'})
					{
						++$delete ;
					}			
				}	
				
				## See if need to delete	
				if ($delete)
				{
					## Remove this entry
					delete $scan_href->{'pr'}{$chan} if (exists($scan_href->{'pr'}{$chan})) ;
	
	print STDERR " : : REMOVE $chan\n" if $DEBUG>=5 ;
				}
				
			}
		}
		
	}

	## Fallback to standard checks
	@del = () ;
	foreach my $chan (keys %{$scan_href->{'pr'}})
	{
		## check for valid channel
		my $delete = 0 ;
		if (($scan_href->{'pr'}{$chan}{'type'}==1) || ($scan_href->{'pr'}{$chan}{'type'}==2) )
		{

print STDERR " : : $chan : vid=$scan_href->{'pr'}{$chan}{'video'}  aud=$scan_href->{'pr'}{$chan}{'audio'}\n" if $DEBUG >=5;

			## check that this type has the required streams
			if ($scan_href->{'pr'}{$chan}{'type'}==1)
			{
				## video
				if (!$scan_href->{'pr'}{$chan}{'video'} || !$scan_href->{'pr'}{$chan}{'audio'})
				{
					++$delete ;
				}
			}
			else
			{
				## audio
				if (!$scan_href->{'pr'}{$chan}{'audio'})
				{
					++$delete ;
				}
			}

		}
		else
		{
			# remove none video/radio types
			++$delete ;
		}

		push @del, $chan if $delete;
	}

	foreach my $chan (@del)
	{
print STDERR " + del chan \"$chan\"\n" if $DEBUG>=5 ;

		delete $scan_href->{'pr'}{$chan} ;
	}
		
printf STDERR "Merg flag=%d\n", $self->merge  if $DEBUG>=5 ;
prt_data("Current Tuning=", $tuning_href, "Scan before merge=", $scan_href) if $DEBUG>=5 ;

	# Merge results
	if ($self->merge)
	{
		if ($self->_scan_freqs)
		{
			## update the old information with the new iff new has better signal
			$scan_href = Linux::DVB::DVBT::Config::merge_scan_freqs($scan_href, $tuning_href, $VERBOSE) ;
		}
		else
		{
			## just update the old information with the new
			$scan_href = Linux::DVB::DVBT::Config::merge($scan_href, $tuning_href) ;
		}	
prt_data("Merged=", $scan_href) if $DEBUG>=5 ;
	}
	
	# Save results
	$self->tuning($scan_href) ;
	Linux::DVB::DVBT::Config::write($self->config_path, $scan_href) ;

print STDERR "DONE\n" if $DEBUG>=5 ;

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

Returns an ARRAY ref of channel_list information; otherwise returns undef. The array is sorted by logical channel number
and contains HASHes of the form:

	{
		'channel'		=> channel name (e.g. "BBC THREE") 
		'channel_num'	=> the logical channel number (e.g. 7)
		'type'			=> radio or tv channel ('radio' or 'tv')
	}

=cut

sub get_channel_list
{
	my $self = shift ;

	# Get any existing info
	my $channels_aref = $self->channel_list() ;
	
	# If not found, try creating
	if (!$channels_aref)
	{
#print STDERR "create chan list\n" ;

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
				my $tsid = $tuning_href->{'pr'}{$channel_name}{'tsid'} ;
				my $pnr = $tuning_href->{'pr'}{$channel_name}{'pnr'} ;
				$tsid_pnr{$channel_name} = "$tsid-$pnr" ;
			}
			
			my $channel_num=1 ;
			foreach my $channel_name (sort 
				{ 
					my $lcn_a = $tuning_href->{'pr'}{$a}{'lcn'}||0 ;
					my $lcn_b = $tuning_href->{'pr'}{$b}{'lcn'}||0 ;
					if (!$lcn_a || !$lcn_b)
					{
						$tuning_href->{'pr'}{$a}{'tsid'} <=> $tuning_href->{'pr'}{$b}{'tsid'}
						||
						$tuning_href->{'pr'}{$a}{'pnr'} <=> $tuning_href->{'pr'}{$b}{'pnr'} ;
					}
					else
					{
						$lcn_a <=> $lcn_b ;
					}
					
				} 
				keys %{$tuning_href->{'pr'}})
			{
				my $type = $tuning_href->{'pr'}{$channel_name}{'type'} || 1 ;
				push @$channels_aref, { 
					'channel'		=> $channel_name, 
					'channel_num'	=> $tuning_href->{'pr'}{$channel_name}{'lcn'} || $channel_num,
					'type'			=> $type == 1 ? 'tv' : 'radio',
				} ;
				
				++$channel_num ;
			}
		}

#prt_data("TSID-PNR=",\%tsid_pnr) ;
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
	
	print STDERR "Recording to $file for $duration ($seconds secs)\n" if $DEBUG ;

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
		*prt_data = sub {print STDERR Debug::DumpObj::prtstr_data(@_)} ;
	}
	else
	{
		# See if we've got Data Dummper
		if (load_module('Data::Dumper'))
		{
			# Create local function
			*prt_data = sub {print STDERR Data::Dumper->Dump([@_])} ;
		}	
		else
		{
			# Create local function
			*prt_data = sub {print STDERR @_, "\n"} ;
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

#print STDERR "duration($start ($start_mins), $end ($end_mins)) = $duration ($duration_mins)\n" if $this->debug() ;

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
	print STDERR "find $channel_name ...\n" if $DEBUG ;
	
	# start by just seeing if it's the correct name...
	if (exists($tuning_href->{'pr'}{$channel_name}))
	{
		$demux_params_href = $tuning_href->{'pr'}{$channel_name} ;
		print STDERR " + found $channel_name\n" if $DEBUG ;
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
		
		foreach my $chan (keys %{$tuning_href->{'pr'}})
		{
			my $srch_chan = lc $chan ;
			$srch_chan =~ s/\s+//g ;
			
			foreach my $search (keys %search)
			{
				print STDERR " + + checking $search against $srch_chan \n" if $DEBUG>2 ;
				if ($srch_chan eq $search)
				{
					$demux_params_href = $tuning_href->{'pr'}{$chan} ;
					print STDERR " + found $channel_name\n" if $DEBUG ;
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
		
		print STDERR "Read config from $dir\n" if $DEBUG ;
		
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

		print STDERR "Written config to $dir\n" if $DEBUG ;
	}
}

#----------------------------------------------------------------------
# Merge tuning information - overwrites previous with new
#
#	region: 'ts' => 
#		section: '4107' =>
#			field: name = Oxford/Bexley
#
sub merge
{
	my ($new_href, $old_href) = @_ ;

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
# Merge tuning information - checks to ensure new program info has the 
# best strength, and that new program has all of it's settings
#
#	'pr' =>
#	      BBC ONE => 
#	        {
#	          pnr => 4171,
#	          tsid => 4107,
#	          tuned_freq => 57800000,
#	          ...
#	        },
#	'ts' => 
#	      4107 =>
#	        { 
#	          tsid => 4107,   
#			  frequency => 57800000,            
#	          ...
#	        },
#	'freqs' => 
#	      57800000 =>
#	        { 
#	          strength => aaaa,               
#	          snr => bbb,               
#	          ber => ccc,               
#	          ...
#	        },
#
#
sub merge_scan_freqs
{
	my ($new_href, $old_href, $verbose) = @_ ;

#print STDERR "merge_scan_freqs()\n" ;

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
#	print STDERR " + found 2 instances of {$region}{$section}\n" ;
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
#	print STDERR " + checking $region $section  : Strength NEW=$new_strength  OLD=$old_strength\n" ;
							if ($old_strength >= $new_strength)
							{
#	print STDERR " + + keep stronger signal (OLD)\n" ;

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
	
#print STDERR "merge_scan_freqs() - DONE\n" ;
	
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

	print STDERR "Searched $search_path : read dir=".($dir?$dir:"")."\n" if $DEBUG ;
		
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
sub write_dvb_ts
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	foreach my $section (keys %$href)
	{
		print $fh "[$section]\n" ;
		foreach my $field (keys %{$href->{$section}})
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
sub write_dvb_pr
{
	my ($fname, $href) = @_ ;

	open my $fh, ">$fname" or die "Error: Unable to write $fname : $!" ;
	
	foreach my $section (keys %$href)
	{
		print $fh "[$href->{$section}{tsid}-$href->{$section}{pnr}]\n" ;
		foreach my $field (keys %{$href->{$section}})
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

__END__

=back

=head1 ACKNOWLEDGEMENTS

=head3 Debugging

Special thanks to Thomas Rehn, not only for providing feedback on a number of latent bugs but also for his
patience in re-running numerous test versions to gather the debug data I needed. Thanks Thomas.

Also, thanks to Arthur Gidlow for running various tests to debug a scanning issue.


=head3 Gerd Knorr for writing xawtv (see L<http://linux.bytesex.org/xawtv/>)

Some of the C code used in this module is used directly from Gerd's libng. All other files
are entirely written by me, or drastically modified from Gerd's original to (a) make the code
more 'Perl friendly', (b) to reduce the amount of code compiled into the library to just those
functions required by this module.  

=head1 AUTHOR

Steve Price

Please report bugs using L<http://rt.cpan.org>.

=head1 BUGS

None (known) at the moment...


=head1 FUTURE

Subsequent releases will include:

=over 4

=item *

Support for event-driven applications (e.g. POE). I need to re-write some of the C to allow for event-driven hooks (and special select calls)

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Steve Price

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

