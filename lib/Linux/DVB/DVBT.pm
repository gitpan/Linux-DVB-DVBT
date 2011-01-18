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

	## Release the hardware (to allow a new recording to start)
	$dvb->dvb_close() ;
	

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

=head2 Additional Modules

Along with this module, the following extra modules are provided:

=over 4

=item L<Linux::DVB::DVBT::Config>

Configuration files and data utilities

=item L<Linux::DVB::DVBT::Utils>

Miscellaneous utilities

=item L<Linux::DVB::DVBT::Ffmpeg>

Helper module that wraps up useful L<ffmpeg|http://ffmpeg.org/> calls to post-process recorded files. 

=back


=head2 Logical Channel Numbers (LCNs)

Where broadcast, the scan function will gather the logical channel number information for all of the channels. The scan() method now stores the LCN information
into the config files, and makes the list of channels available through the L</get_channel_list()> method. So you can now get the channel number you
see (and enter) on any standard freeview TV or PVR.

This is of most interest if you want to use the L</epg()> method to gather data to create a TV guide. Generally, you'd like the channel listings
to be sorted in the order to which we've all become used to through TV viewing (i.e. it helps to have BBC1 appear before channel 4!). 


=head2 TVAnytime

New in this version is the gathering of TV Anytime series and program information by the epg function. Where available, you now have a 'tva_series' and 
'tva_program' field in the epg HASH that contains the unique TV Anytime number for the series and program respectfully. This is meant to ensure that 
you can determine the program and series uniquely and allow you to not re-record programs. In reality, I've found that some broadcasters use different
series identifiers even when the same series is shown at a different time!

At present, I use the series identifier to group recordings within a series (I then rename the series directory something more meaningful!). Within a 
series, the program identifier seems to be useable to determine if the program has been recorded before.


=head2 Multiplex Recording

Another new feature in this version is support for multiplex recording (i.e. being able to record multiple streams/programs at the same time, as long as they are all
in the same multiplex). As you can imagine, specifying the recording of multiple programs (many of which will be different lengths and start at 
diffent times) can get quite involved. 

To simplify these tasks in your scripts, I've written various "helpers" that handle parsing command line arguments, through to optionally running
ffmpeg to transcode the recorded files. These are all in addition to the base function that adds a demux filter to the list that will be recorded
(see L</add_demux_filter($pid, $pid_type [, $tsid])>). Feel free to use as much (or as little) of the helper functions as you like - you can always write
your own scripts using add_demux_filter().

For details of the ffmpeg helper functions, please see L<Linux::DVB::DVBT::Ffmpeg>. Obviously, you need to have ffmpeg installed on your system
for any of the functions to work!

To record multiple channels (in the same multiplex) at once, you need something like:

	use Linux::DVB::DVBT;

	## Parse command line
	my @chan_spec ;
	my $error = $dvb->multiplex_parse(\@chan_spec, @ARGV);
	
	## Select the channel(s)
	my %options = (
		'lang'		=> $lang,
		'out'		=> $out,
		'tsid'		=> $tsid,
	) ;
	$error = $dvb->multiplex_select(\@chan_spec, %options) ;
	
	## Get multiplex info
	my %multiplex_info = $dvb->multiplex_info() ;

	## Record
	$dvb->multiplex_record(%multiplex_info) ;

	## Release the hardware (to allow a new recording to start)
	$dvb->dvb_close() ;
	
	## [OPTIONAL] Transcode the recordings (uses ffmpeg helper module)
	$error = $dvb->multiplex_transcode(%multiplex_info) ;

Note, the old L<record()|/record($file, $duration)> function has been re-written to use the same underlying multiplex functions. This means that,
even though you are only recording a single program, you can still use the ffmpeg helper transcode functions after the 
recording has finished. For example:

	## Record
	$dvb->record("$dir$name$ext", $duration) ;
	
	## Release DVB (for next recording)
	$dvb->dvb_close() ;
	
	## Get multiplex info
	my %multiplex_info = $dvb->multiplex_info() ;
	
	## Transcode the recordings (uses ffmpeg helper module)
	$dvb->multiplex_transcode(%multiplex_info) ;
	
	## Display ffmpeg output / warnings / errors
	foreach my $line (@{$multiplex_info{'lines'}})
	{
		info("[ffmpeg] $line") ;
	}
	
	foreach my $line (@{$multiplex_info{'warnings'}})
	{
		info("[ffmpeg] WARN: $line") ;
	}
	
	foreach my $line (@{$multiplex_info{'errors'}})
	{
		info("[ffmpeg] ERROR: $line") ;
	}

Since this is a new feature, I've left access to the original recording method but renamed it L<record_v1()|/record_v1($file, $duration)>. If, for any reason,
you wish to use the original recording method, then you need to change your scripts to call the renamed function. But please contact me if you are
having problems, and I will do my best to fix them. Future releases will eventually drop the old recording method.


=head2 Example Scripts

Example scripts have been provided in the package which illustrate the expected use of the package (and
are useable programs in themeselves). To see the full man page of each script, simply run it with the '-man' option.

=over 4

=item L<dvbt-devices|Linux::DVB::DVBT::..::..::..::script::dvbt-devices>

Shows information about fited DVB-T tuners

=item L<dvbt-scan|Linux::DVB::DVBT::..::..::..::script::dvbt-scan>

Run this by providing the frequency file (usually stored in /usr/share/dvb/dvb-t). If run as root, this will set up the configuration
files for all users. For example:

   $ dvbt-scan /usr/share/dvb/dvb-t/uk-Oxford

NOTE: Frequency files are provided by the 'dvb' rpm package available for most distros

=item L<dvbt-chans|Linux::DVB::DVBT::..::..::..::script::dvbt-chans>

Use to display the current list of tuned channels. Shows them in logical channel number order. The latest version shows information on
the PID numbers for the video, audio, teletext, and subtitle streams that make up each channel.

It also now has the option (-multi) to display the channels grouped into their multiplexes (i.e. their transponder or TSIDs). This becomes
really useful if you want to schedule a multiplex recording and need to check which channels you can record at the same time. 


=item L<dvbt-epg|Linux::DVB::DVBT::..::..::..::script::dvbt-epg>

When run, this grabs the latest EPG information and prints out the program guide:

   $ dvbt-epg

NOTE: This process can take quite a while (it takes around 30 minutes on my system), so please be patient.

=item L<dvbt-record|Linux::DVB::DVBT::..::..::..::script::dvbt-record>

Specify the channel, the duration, and the output filename to record a channel:

   $ dvbt-record "bbc1" spooks.ts 1:00 
   
Note that the duration can be specified as an integer (number of minutes), or in HH:MM format (for hours and minutes)

=item L<dvbt-ffrec|Linux::DVB::DVBT::..::..::..::script::dvbt-ffrec>

Similar to dvbt-record, but pipes the transport stream into ffmpeg and uses that to transcode the data directly into an MPEG file (without
saving the transport stream file).

Specify the channel, the duration, and the output filename to record a channel:

   $ dvbt-ffrec "bbc1" spooks.mpeg 1:00 
   
Note that the duration can be specified as an integer (number of minutes), or in HH:MM format (for hours and minutes)

It's worth mentioning that this relies on ffmpeg operating correctly. Some versions of ffmpeg are fine; others have failed reporting:

  "error, non monotone timestamps"

which appear to be related to piping the in via stdin (running ffmpeg on a saved transport stream file always seems to work) 

=item L<dvbt-multirec|Linux::DVB::DVBT::..::..::..::script::dvbt-multirec>

Record multiple channels at the same time (as long as they are all in the same multiplex).

Specify each recording with a filename, duration, and optional offset start time. Then specify the channel name, or a list of the pids you
want to record. Repeat this for every file you want to record.

For example, you want to record some programs starting at 13:00. The list of programs are:

=over 4

=item * ITV2 start 13:00, duration 0:30

=item * FIVE start 13:15, duration 0:30

=item * ITV1 start 13:30, duration 0:30

=item * More 4 start 13:15, duration 0:05

=item * E4 start 13:05, duration 0:30

=item * Channel 4+1 start 13:05, duration 1:30

=back

To record these (running the script at 13:00) use:

   $ dvbt-multirec file=itv2.mpeg ch=itv2 len=0:30  \
   	               file=five.mpeg ch=five len=0:30 off=0:15 \
   	               file=itv1.mpeg ch=itv1 len=0:30 off=0:30 \
   	               file=more4.mpeg ch=more4 len=0:05 off=0:15 \
   	               file=e4.mpeg ch=e4 len=0:30 off=0:05 \
   	               file=ch4+1.mpeg ch='channel4+1' len=1:30 off=0:05 
   

=back


=head2 HISTORY

I started this package after being lent a Hauppauge WinTV-Nova-T usb tuner (thanks Tim!) and trying to 
do some command line recording. After I'd failed to get most applications to even talk to the tuner I discovered
xawtv (L<http://linux.bytesex.org/xawtv/>), started looking at it's source code and started reading the DVB-T standards.

This package is the result of various expermients and is being used for my web TV listing and program
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

use Linux::DVB::DVBT::Config ;
use Linux::DVB::DVBT::Utils ;
use Linux::DVB::DVBT::Ffmpeg ;

#============================================================================================
# EXPORTER
#============================================================================================
require Exporter;
our @ISA = qw(Exporter);

#============================================================================================
# GLOBALS
#============================================================================================
our $VERSION = '2.06';
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

This is a HASH ref containing the parameters used in the last call to L</set_frontend(%params)> (either externally or internally by this module).

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

Set this field to one of 'die' (the default), 'return', or 'message' and when an error occurs that error mode action will be taken.

If the mode is set to 'die' then the application will terminate after printing all of the errors stored in the errors list (see L</errors> field).
When the mode is set to 'return' then the object method returns control back to the calling application with a non-zero status (which is actually the 
current count of errors logged so far). Similalrly, if the mode is set to 'message' then the object method simply returns the error message. 
It is the application's responsibility to handle the errors (stored in  L</errors>) when setting the mode to 'return' or 'message'.

=item B<timeout> - Timeout

Set hardware timeout time in milliseconds. Most hardware will be ok using the default (900ms), but you can use this field to increase
the timeout time. 

=item B<add_si> - Automatically add SI tables

By default, recorded files automatically have the SI tables (the PAT & PMT for the program) recorded along with the
usual audio/video streams. This is the new default since the latest version of ffmpeg refuses to understand the
encoding of any video streams unless this information is added.

If you really want to, you can change this flag to 0 to prevent SI tables being added in all cases.

NOTE: You still get the tables whenever you add subtitles.


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
					prune_channels
					add_si
					
					_scan_freqs
					_device_index
					_device_info
					_demux_filters
					_multiplex_info
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
	'config_path'	=> $Linux::DVB::DVBT::Config::DEFAULT_CONFIG_PATH,

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

	# remove un-tuneable channels
	'prune_channels'	=> 1,
	
	# Automatically add SI tables to recording
	'add_si'		=> 1,
	
	######################################
	# Internal
	
	# scanning driven by frequency file
	'_scan_freqs'		=> 0,
	
	# which device in the device list are we
	'_device_index' 	=> undef,
	
	# ref to this device's info from the device list
	'_device_info'		=> undef,
	
	# list of demux filters currently active
	'_demux_filters'	=> [],
	
	# list of multiplex recordings scheduled
	'_multiplex_info'	=> {},
) ;

# Frequency must be at least 100 MHz
# The Stockholm agreement of 1961 says:
#   Band III  : 174 MHz - 230 MHz
#   Band IV/V : 470 MHz - 826 MHz
#
# Current dvb-t files range: 177.5 MHz - 858 MHz
#
# So 100 MHz allows for country "variations"!
#
my $MIN_FREQ = 100000000 ;

# Maximum PID value
my $MAX_PID = 0x2000 ;

# code value to use 'auto' setting
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

my %FE_INV = (
	'NONE'		=> 0,
	'0'			=> 0,
	'1'			=> 1,
	'AUTO'		=> $AUTO,
) ;		

## All FE params
my %FE_PARAMS = (
	bandwidth 			=> \%FE_BW,
	code_rate_high 		=> \%FE_CODE_RATE,
	code_rate_low 		=> \%FE_CODE_RATE,
	modulation 			=> \%FE_MOD,
	transmission 		=> \%FE_TRANSMISSION,
	guard_interval 		=> \%FE_GUARD,
	hierarchy 			=> \%FE_HIER,
	inversion 			=> \%FE_INV,
) ;

my %FE_CAPABLE = (
	bandwidth 			=> 'FE_CAN_BANDWIDTH_AUTO',
	code_rate_high 		=> 'FE_CAN_FEC_AUTO',
	code_rate_low 		=> 'FE_CAN_FEC_AUTO',
	modulation 			=> 'FE_CAN_QAM_AUTO',
	transmission 		=> 'FE_CAN_TRANSMISSION_MODE_AUTO',
	guard_interval 		=> 'FE_CAN_GUARD_INTERVAL_AUTO',
	hierarchy 			=> 'FE_CAN_HIERARCHY_AUTO',
	inversion			=> 'FE_CAN_INVERSION_AUTO',
) ;


## ETSI 300 468 SI TABLES
my %SI_TABLES = (
	# MPEG-2
	'PAT'		=> 0x00,
	'CAT'		=> 0x01,
	'TSDT'		=> 0x02,
	
	# DVB
	'NIT'		=> 0x10,
	'SDT'		=> 0x11,
	'EIT'		=> 0x12,
	'RST'		=> 0x13,
	'TDT'		=> 0x14,
) ;

my %SI_LOOKUP = reverse %SI_TABLES ;

my %EPG_FLAGS = (
    'AUDIO_MONO'      => (1 << 0),
    'AUDIO_STEREO'    => (1 << 1),
    'AUDIO_DUAL'      => (1 << 2),
    'AUDIO_MULTI'     => (1 << 3),
    'AUDIO_SURROUND'  => (1 << 4),

    'VIDEO_4_3'       => (1 << 8),
    'VIDEO_16_9'      => (1 << 9),
    'VIDEO_HDTV'      => (1 << 10),

    'SUBTITLES'       => (1 << 16),
) ;


#============================================================================================

=head2 CONSTRUCTOR

=over 4

=cut

#============================================================================================

=item B<new([%args])>

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
	unless($self->{dvb})
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

	$self->dvb_close() ;
}


#-----------------------------------------------------------------------------

=item B<dvb_close()>

Close the hardware down (for example, to allow another script access), without
destroying the object.

=cut

sub dvb_close
{
	my $self = shift ;

	if (ref($self->{dvb}))
	{
		## Close any open demux filters
		$self->close_demux_filters() ;

		## Free up hardware
		dvb_fini($self->dvb) ;
		
		$self->{dvb} = undef ;
	}
}



#============================================================================================

=back

=head2 CLASS METHODS

Use as Linux::DVB::DVBT->method()

=over 4

=cut

#============================================================================================

#-----------------------------------------------------------------------------

=item B<debug([$level])>

Set new debug level. Returns setting.

=cut

sub debug
{
	my ($obj, $level) = @_ ;

	if (defined($level))
	{
		$DEBUG = $level ;
		
		## Set utility module debug levels
		$Linux::DVB::DVBT::Config::DEBUG = $DEBUG ;
		$Linux::DVB::DVBT::Utils::DEBUG = $DEBUG ;
		$Linux::DVB::DVBT::Ffmpeg::DEBUG = $DEBUG ;
	}

	return $DEBUG ;
}

#-----------------------------------------------------------------------------

=item B<dvb_debug([$level])>

Set new debug level for dvb XS code

=cut

sub dvb_debug
{
	my ($obj, $level) = @_ ;

	dvb_set_debug($level||0) ;
}

#-----------------------------------------------------------------------------

=item B<verbose([$level])>

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

=item B<device_list()>

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

#----------------------------------------------------------------------------

=item B<is_error()>

If there was an error during one of the function calls, returns the error string; otherwise
returns "".

=cut

sub is_error
{
	my ($class) = @_ ;
	my $error_str = dvb_error_str() ;
	
	if ($error_str =~ /no error/i)
	{
		$error_str = "" ;
	}
	return $error_str ;
}


#============================================================================================

=back

=head2 OBJECT METHODS

=over 4

=cut

#============================================================================================

#----------------------------------------------------------------------------

=item B<set(%args)>

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

#----------------------------------------------------------------------------

=item B<handle_error($error_message)>

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
	elsif ($mode =~ m/message/i)
	{
		# return this error message
		return $error_message ;
	}	
	elsif ($mode =~ m/die/i)
	{
		# Die showing all logged errors
		croak join ("\n", @{$self->errors()}) ;
	}	
}


#============================================================================================

=back

=head3 SCANNING

=over 4

=cut

#============================================================================================

#----------------------------------------------------------------------------

=item B<scan()>

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

	# hardware closed
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

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
	#    freqs => 
	#    { # HASH(0x844d76c)
	#      482000000 => 
	#        { # HASH(0x8448da4)
	#          'seen' => 1,
	#          'strength' => 0,
	#          'tuned' => 0,
	#        },
	#
	#    '177500000' => {
	#		'guard_interval' => 2,
	#		'transmission' => 4,
	#		'code_rate_high' => 16,
	#		'tuned' => 1,
	#		'strength' => 49420,
	#		'modulation' => 2,
	#		'seen' => 1,
	#		'bandwidth' => 7,
	#		'code_rate_low' => 16,
	#		'hierarchy' => 0,
	#		'inversion' => 2
	#		}
#readback tuning:
#    __u32                   frequency=177500000
#    fe_spectral_inversion_t inversion=2 (auto)
#    fe_bandwidth_t          bandwidthy=1 (7 MHz)
#    fe_code_rate_t          code_rate_HPy=3 (3/4)
#    fe_code_rate_t          code_rate_LP=1 (1/2)
#    fe_modulation_t         constellation=3 (64)
#    fe_transmit_mode_t      transmission_mod=1 (8k)
#    fe_guard_interval_t     guard_interval=0 (1/32)
#    fe_hierarchy_t          hierarchy_information=0 (none)
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
	#  lcn =>
	#    { # HASH(0x83d2608)
	#      $tsid =>
	#        { # HASH(0x8442524)
	#          $pnr =>
	#            { # HASH(0x8442578)
	#              lcn => 20,
	#              service_type => 2,
	#              visible => 1,
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

	## Collect together LCN info and map TSIDs to transponder settings
	my %tsids ;
	foreach my $ts_href (@{$raw_scan_href->{'ts'}})
	{
		my $tsid = $ts_href->{'tsid'} ;
		
		# handle LCN
		my $lcn_href = delete $ts_href->{'lcn'} ;
		foreach my $pnr (keys %$lcn_href)
		{
			$scan_href->{'lcn'}{$tsid}{$pnr} = $lcn_href->{$pnr} ;
		}

		# set TSID
		$tsids{$tsid} = $ts_href ;
		$tsids{$tsid}{'frequency'} = undef ;
	}	

if ($VERBOSE >= 2)
{
print STDERR "\n========================================================\n" ;
foreach my $ts_href (@{$raw_scan_href->{'ts'}})
{
	my $tsid = $ts_href->{'tsid'} ;
	print STDERR "--------------------------------------------------------\n" ;
	print STDERR "TSID $tsid\n" ;
	print STDERR "--------------------------------------------------------\n" ;
	
	foreach my $prog_href (@{$raw_scan_href->{'pr'}})
	{
		my $ptsid = $prog_href->{'tsid'} ;
		next unless $ptsid == $tsid ;
		
		my $name = $prog_href->{'name'} ;
		my $pnr = $prog_href->{'pnr'} ;
		my $lcn = $scan_href->{'lcn'}{$tsid}{$pnr} ;
		$lcn = $lcn ? sprintf("%2d", $lcn) : "??" ;
		
		my $freqs_aref = $prog_href->{'freqs'} ;
		
		print STDERR "  $lcn : [$pnr] $name - " ;
		foreach my $freq (@$freqs_aref)
		{
			print STDERR "$freq Hz " ;
		}
		print STDERR "\n" ;

	}
}	
print STDERR "\n========================================================\n" ;
}

	## Use program info to map TSID to freq (choose strongest signal where necessary)
	foreach my $prog_href (@{$raw_scan_href->{'pr'}})
	{
		my $tsid = $prog_href->{'tsid'} ;
		my $name = $prog_href->{'name'} ;
		my $pnr = $prog_href->{'pnr'} ;
		
		my $freqs_aref = delete $prog_href->{'freqs'} ;
		next unless @$freqs_aref ;
		my $freq = @{$freqs_aref}[0] ;
		
		# handle multiple freqs
		if (@$freqs_aref >= 2)
		{
			foreach my $new_freq (@$freqs_aref)
			{
				if ($new_freq != $freq)
				{
					# check strengths
					my $new_strength = $raw_scan_href->{'freqs'}{$freq}{'strength'} ;
					my $old_strength = $raw_scan_href->{'freqs'}{$new_freq}{'strength'} ;
					if ($new_strength > $old_strength)
					{
						print STDERR "  Program \"$name\" ($pnr) with multiple freqs : using new signal $new_strength (old $old_strength) change freq from $freq to $new_freq\n" if $VERBOSE ;
						$freq = $new_freq ;
					}
				}
			}
		}
		
		# save program data
		$scan_href->{'pr'}{$name} = $prog_href ;
		if (exists($scan_href->{'lcn'}{$tsid}) && exists($scan_href->{'lcn'}{$tsid}{$pnr}))
		{
			$scan_href->{'pr'}{$name}{'lcn'} = $scan_href->{'lcn'}{$tsid}{$pnr}{'lcn'} ;
		}
		
		# Set transponder freq
		$tsids{$tsid}{'frequency'} = $freq ; 
		$scan_href->{'ts'}{$tsid} = $tsids{$tsid} ;
	}
	

prt_data("Scan results=", $scan_href) if $DEBUG>=5 ;
print STDERR "process rest...\n" if $DEBUG>=5 ;
	
	## Post-process to weed out undesirables!
	my %tsid_map ;
	my @del ;
	foreach my $chan (keys %{$scan_href->{'pr'}})
	{
		# strip out chans with no names (or just spaces)
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

				# skip delete if pruning not required
				$delete = 0 unless $self->prune_channels ;
			
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

		# skip delete if pruning not required
		$delete = 0 unless $self->prune_channels ;

		push @del, $chan if $delete;
	}

	foreach my $chan (@del)
	{
print STDERR " + del chan \"$chan\"\n" if $DEBUG>=5 ;

		delete $scan_href->{'pr'}{$chan} ;
	}

prt_data("Scan before tsid fix=", $scan_href) if $DEBUG>=5 ;


	## Set transponder params 
	
	# sadly there are lies, damn lies, and broadcast information! You can't rely on the broadcast info and
	# have to fall back on either readback from the tuner device for it's settings (if it supports readback),
	# using the values specified in the frequency file (i.e. the tuning params), or defaulting params to 'AUTO'
	# where the tuner will permit it.
	
	# this is what we used to set the frontend with
	my $frontend_params_href = $self->frontend_params() ;
		
	foreach my $tsid (keys %{$scan_href->{'ts'}})
	{
		my $freq = $tsids{$tsid}{'frequency'} ;
		if (exists($scan_href->{'freqs'}{$freq}))
		{
			# Use readback info for preference
			foreach (keys %{$scan_href->{'freqs'}{$freq}} )
			{
				$tsids{$tsid}{$_} = $scan_href->{'freqs'}{$freq}{$_} ;
			}
		}
		elsif ($freq == $frontend_params_href->{'frequency'})
		{
			# Use specified settings
			foreach (keys %{$frontend_params_href} )
			{
				$tsids{$tsid}{$_} = $frontend_params_href->{$_} ;
			}
		}
		else
		{
			# device info
			my $dev_info_href = $self->_device_info ;
			my $capabilities_href = $dev_info_href->{'capabilities'} ;

			# Use AUTO where possible
			foreach my $param (keys %{$frontend_params_href} )
			{
				next unless exists($FE_CAPABLE{$param}) ;

				## check to see if we are capable of using auto
				if ($capabilities_href->{$FE_CAPABLE{$param}})
				{
					# can use auto
					$tsids{$tsid}{$param} = $AUTO ;
				}
			}
		}
	}	
		
		
printf STDERR "Merge flag=%d\n", $self->merge  if $DEBUG>=5 ;
prt_data("FE params=", $frontend_params_href, "Scan before merge=", $scan_href) if $DEBUG>=5 ;

	## Merge results
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

=item B<scan_from_file($freq_file)>

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

	## Need a file
	return $self->handle_error( "Error: No frequency file specified") unless $freq_file ;

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

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
				inversion => 0,
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
			my $rc = -1 ;
			my %tuning_params ;
			my $tuning_params_href = shift @tuning_list ;
			
			# make sure frequency is valid
			if ($tuning_params_href->{'frequency'} >= $MIN_FREQ)
			{

				# convert file entry into a frontend param
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
				$rc = dvb_scan_tune($self->{dvb}, {%tuning_params}) ;
			}
			
			## If tuning went ok, then save params
			if ($rc == 0)
			{
				$self->frontend_params( {%tuning_params} ) ;
				$tuned = 1 ;
			}
			else
			{
				my $freq = $tuning_params{'frequency'} || "0" ;
				print STDERR "    Failed to set the DVB-T tuner to $freq Hz ... skipping\n" ;

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




#============================================================================================

=back

=head3 TUNING

=over 4

=cut

#============================================================================================

#----------------------------------------------------------------------------

=item B<set_frontend(%params)>

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
    'tsid'

(If you don't know what these parameters should be set to, then I recommend you just use the L</select_channel($channel_name)> method)

Returns 0 if ok; error code otherwise

=cut

sub set_frontend
{
	my $self = shift ;
	my (%params) = @_ ;

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	# Set up the frontend
	my $rc = dvb_tune($self->{dvb}, {%params}) ;
	
	print STDERR "dvb_tune() returned $rc\n" if $DEBUG ;
	
	# If tuning went ok, then save params
	#
	# Currently:
	#   -11 = Device busy
	#	-15 / -16 = Failed to tune
	#
	if ($rc == 0)
	{
		$self->frontend_params( {%params} ) ;
	}
	
	return $rc ;
}

#----------------------------------------------------------------------------

=item B<set_demux($video_pid, $audio_pid, $subtitle_pid, $teletext_pid)>

Selects a particular video/audio stream (and optional subtitle and/or teletext streams) and sets the
demultiplexer to those streams (ready for recording).

(If you don't know what these parameters should be set to, then I recommend you just use the L</select_channel($channel_name)> method)

Returns 0 for success; error code otherwise.

=cut

sub set_demux
{
	my $self = shift ;
	my ($video_pid, $audio_pid, $subtitle_pid, $teletext_pid, $tsid, $demux_params_href) = @_ ;

print STDERR "set_demux( <$video_pid>, <$audio_pid>, <$teletext_pid> )\n" if $DEBUG ;

	my $error = 0 ;
	if ($video_pid && !$error)
	{
		$error = $self->add_demux_filter($video_pid, "video", $tsid, $demux_params_href) ;
	}
	if ($audio_pid && !$error)
	{
		$error = $self->add_demux_filter($audio_pid, "audio", $tsid, $demux_params_href) ;
	}
	if ($teletext_pid && !$error)
	{
		$error = $self->add_demux_filter($teletext_pid, "teletext", $tsid, $demux_params_href) ;
	}
	if ($subtitle_pid && !$error)
	{
		$error = $self->add_demux_filter($subtitle_pid, "subtitle", $tsid, $demux_params_href) ;
	}
	return $error ;
}

#----------------------------------------------------------------------------

=item B<select_channel($channel_name)>

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

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

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

	## start with clean slate
	$self->multiplex_close() ;	

	# Set demux (no teletext or subtitle)
	if ($self->set_demux(
		$demux_params_href->{'video'}, 
		$demux_params_href->{'audio'},
		0, 
		0, 
		$frontend_params_href->{'tsid'}, 
		$demux_params_href) 
	)
	{
		return $self->handle_error("Unable to set demux") ;
	}

	return 0 ;
}
	
#----------------------------------------------------------------------------

=item B<get_tuning_info()>

Check to see if 'tuning' information has been set. If not, attempts to read from the config
search path.

Returns a HASH ref of tuning information - i.e. it contains the complete information on all
transponders (under the 'ts' field), and all programs (under the 'pr' field). [see L</scan()> method for format].

Otherwise returns undef if no information is available.

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

=item B<get_channel_list()>

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
					'type'			=> $type == 1 ? 'tv' :  ($type == 2 ? 'radio' : 'special'),
					'type_code'		=> $type,
				} ;
				
				++$channel_num ;
			}
		}

#prt_data("TSID-PNR=",\%tsid_pnr) ;
	}

	return $channels_aref ;
}

#----------------------------------------------------------------------------

=item B<signal_quality()>

Measures the signal quality of the currently tuned transponder. Returns a HASH ref containing:

	{
		'ber'					=> Bit error rate (32 bits)
		'snr'					=> Signal to noise ratio (maximum is 0xffff)
		'strength'				=> Signal strength (maximum is 0xffff)
		'uncorrected_blocks'	=> Number of uncorrected blocks (32 bits)
		'ok'					=> flag set if no errors occured during the measurements
	}

Note that some tuner hardware may not support some (or any) of the above measurements.

=cut

sub signal_quality
{
	my $self = shift ;
	

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	# if not tuned yet, tune to all station freqs (assumes scan has been performed)
	if (!$self->frontend_params())
	{
		return $self->handle_error("Frontend not tuned") ;
	}

	# get signal info
	my $signal_href = dvb_signal_quality($self->{dvb}) ;
	
	return $signal_href ;
}

#----------------------------------------------------------------------------

=item B<tsid_signal_quality([$tsid])>

Measures the signal quality of the specified transponder. Returns a HASH containing:

	{
		$tsid => {
			'ber'					=> Bit error rate (32 bits)
			'snr'					=> Signal to noise ratio (maximum is 0xffff)
			'strength'				=> Signal strength (maximum is 0xffff)
			'uncorrected_blocks'	=> Number of uncorrected blocks (32 bits)
			'ok'					=> flag set if no errors occured during the measurements
			'error'					=> Set to an error string on error; otherwise undef
		}
	}

If no TSID is specified, then scans all transponders and returns the complete HASH.

Note that some tuner hardware may not support some (or any) of the above measurements.

=cut

sub tsid_signal_quality
{
	my $self = shift ;
	my ($tsid) = @_ ;
	

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	# ensure we have the tuning info
	my $tuning_href = $self->get_tuning_info() ;
	if (! $tuning_href)
	{
		return $self->handle_error("Unable to get tuning information") ;
	}

	# check/create list of TSIDs
	my @tsids ;
	if ($tsid)
	{
		# check it
		if (!exists($tuning_href->{'ts'}{$tsid}))
		{
			# Raise an error
			return $self->handle_error("Unknown TSID $tsid") ;
		}
		
		push @tsids, $tsid ;
	}
	else
	{
		# create
		@tsids = keys %{$tuning_href->{'ts'}} ;
	}
	
	## handle errors
	my $errmode = $self->{errmode} ;
	$self->{errmode} = 'message' ;
	
	## get info
	my %info ;
	foreach my $tsid (@tsids)
	{
		## Tune frontend
		my $frontend_params_href = $tuning_href->{'ts'}{$tsid} ;
		my $error_code ;
		if ($error_code = $self->set_frontend(%$frontend_params_href, 'timeout' => $self->timeout))
		{
			print STDERR "set_frontend() returned $error_code\n" if $DEBUG ;
			
			$info{$tsid}{'error'} = "Unable to tune frontend. " . dvb_error_str() ;
			if ($info{$tsid}{'error'} =~ /busy/i)
			{
				## stop now since the device is in use
				last ;
			}
		}
		else
		{
			## get info
			$info{$tsid} = $self->signal_quality($tsid) ;
			$info{$tsid}{'error'} = undef ;
		}
	}
	
	## restore error handling
	$self->{errmode} = $errmode ;
	
	
	## return info
	return %info ;
}



#============================================================================================

=back

=head3 RECORDING

=over 4

=cut

#============================================================================================

#----------------------------------------------------------------------------

=item B<record($file, $duration)>

(New version that uses the underlying multiplex recording methods).

Streams the selected channel information (see L</select_channel($channel_name)>) into the file $file for $duration.

The duration may be specified either as an integer number of minutes, or in HH:MM format (for hours & minutes), or in
HH:MM:SS format (for hours, minutes, seconds).

Note that (if possible) the method creates the directory path to the file if it doersn't already exist.

=cut

sub record
{
	my $self = shift ;
	my ($file, $duration) = @_ ;

print STDERR "record($file, $duration)" if $DEBUG ;

	## need filename
	return $self->handle_error("No valid filename specified") unless ($file) ;

	## need valid duration
	my $seconds = Linux::DVB::DVBT::Utils::time2secs($duration) ;
	return $self->handle_error("No valid duration specified") unless ($seconds) ;

	## Set up the multiplex info for this single file

	# get entry for this file (or create it)
	my $href = $self->_multiplex_file_href($file) ;
	
	# set time
	$href->{'duration'} = $seconds ;
	
	# set total length
	$self->{_multiplex_info}{'duration'} = $seconds ;
			
	# set demux filter info
	push @{$href->{'demux'}}, @{$self->{_demux_filters}};

	# get tsid
	my $frontend_href = $self->frontend_params() ;
	my $tsid = $frontend_href->{'tsid'} ;
	
	## Add in SI tables (if required) to the multiplex info
	my $error = $self->_add_required_si($tsid) ;
	$self->handle_error($error) if ($error) ;
	
	## ensure pid lists match the demux list
	$self->_update_multiplex_info($tsid) ;


	## Now record
Linux::DVB::DVBT::prt_data("multiplex_info=", $self->{'_multiplex_info'}) if $DEBUG>=10 ;

	return $self->multiplex_record(%{$self->{'_multiplex_info'}}) ;
}

#----------------------------------------------------------------------------

=item B<record_v1($file, $duration)>

Old version 1.xxx style recording. Kept in case newer version does something that you weren't
expecting. Note that this version will be phased out and removed in future releases. 

Streams the selected channel information (see L</select_channel($channel_name)>) into the file $file for $duration.

The duration may be specified either as an integer number of minutes, or in HH:MM format (for hours & minutes), or in
HH:MM:SS format (for hours, minutes, seconds).

Note that (if possible) the method creates the directory path to the file if it doersn't already exist.

=cut

sub record_v1
{
	my $self = shift ;
	my ($file, $duration) = @_ ;

	## need filename
	return $self->handle_error("No valid filename specified") unless ($file) ;

	## need valid duration
	my $seconds = Linux::DVB::DVBT::Utils::time2secs($duration) ;
	return $self->handle_error("No valid duration specified") unless ($seconds) ;

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	## ensure directory is present
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



#============================================================================================

=back

=head3 EPG

=over 4

=cut

#============================================================================================


#----------------------------------------------------------------------------

=item B<epg()>

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
		'pid'			=> program unique id (= $pid)
		'channel'		=> channel name
		
		'date'			=> date
		'start'			=> start time
		'end'			=> end time
		'duration'		=> duration
		
		'title'			=> title string
		'text'			=> synopsis string
		'etext'			=> extra text (not usually used)
		'genre'			=> genre string
		
		'episode'		=> episode number
		'num_episodes' => number of episodes

		'subtitle'		=> this is a short program name (useful for saving as a filename)
		
		'tva_prog'		=> TV Anytime program id
		'tva_series'	=> TV Anytime series id
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

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

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
			
			if ($DEBUG)
			{
				print STDERR "FREQ LIST:\n" ;
				foreach (@next_freq)
				{
					print STDERR "  $_ Hz\n" ;
				}
			}
			
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

	printf("Found %d EPG entries\n", scalar(@$epg_data)) if $VERBOSE ;

prt_data("EPG data=", $epg_data) if $DEBUG>=2 ;

	## get epg statistics
	my $epg_stats = dvb_epg_stats($self->{dvb}) ;


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
		
prt_data("EPG raw entry ($chan)=", $epg_entry) if $DEBUG>=2 ;
		
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
			
		my $epg_flags = $epg_entry->{'flags'} ;
		
		$epg{$chan}{$pid} = {
			'pid'		=> $pid,
			'channel'	=> $chan,
			
			'date'		=> $date,
			'start'		=> $start,
			'end'		=> $end,
			'duration'	=> $duration,
			
			'title'		=> $title,
			'subtitle'	=> Linux::DVB::DVBT::Utils::subtitle($synopsis),
			'text'		=> $synopsis,
			'etext'		=> $etext,
			'genre'		=> $epg_entry->{'genre'},

			'episode'	=> $episode,
			'num_episodes' => $num_episodes,
			
			'tva_prog'	=> $epg_entry->{'tva_prog'} || '',
			'tva_series'=> $epg_entry->{'tva_series'} || '',

			#    'AUDIO_MONO'      => (1<<0),
			#    'AUDIO_STEREO'    => (1<<1),
			#    'AUDIO_DUAL'      => (1<<2),
			#    'AUDIO_MULTI'     => (1<<3),
			#    'AUDIO_SURROUND'  => (1<<4),
			#
			#    'VIDEO_4_3'       => (1<< 8),
			#    'VIDEO_16_9'      => (1<< 9),
			#    'VIDEO_HDTV'      => (1<<10),
			#
			#    'SUBTITLES'       => (1<<16),
			
			'flags'		=> {
				'mono'			=> $epg_flags & $EPG_FLAGS{'AUDIO_MONO'} ? 1 : 0,
				'stereo'		=> $epg_flags & $EPG_FLAGS{'AUDIO_STEREO'} ? 1 : 0,
				'dual-mono'		=> $epg_flags & $EPG_FLAGS{'AUDIO_DUAL'} ? 1 : 0,
				'multi'			=> $epg_flags & $EPG_FLAGS{'AUDIO_MULTI'} ? 1 : 0,
				'surround'		=> $epg_flags & $EPG_FLAGS{'AUDIO_SURROUND'} ? 1 : 0,

				'4:3'			=> $epg_flags & $EPG_FLAGS{'VIDEO_4_3'} ? 1 : 0,
				'16:9'			=> $epg_flags & $EPG_FLAGS{'VIDEO_16_9'} ? 1 : 0,
				'hdtv'			=> $epg_flags & $EPG_FLAGS{'VIDEO_HDTV'} ? 1 : 0,

				'subtitles'		=> $epg_flags & $EPG_FLAGS{'SUBTITLES'} ? 1 : 0,
			},
		} ;

prt_data("EPG final entry ($chan) $pid=", $epg{$chan}{$pid}) if $DEBUG>=2 ;

	}
	
	## analyse statistics
	my %epg_statistics ;
	$epg_statistics{'totals'} = $epg_stats->{'totals'} ;
	foreach my $part_href (@{$epg_stats->{'parts'}})
	{
		my ($tsid, $pnr, $parts, $parts_left) = @{$part_href}{qw/tsid pnr parts parts_left/} ;
		$epg_statistics{'parts'}{$tsid}{$pnr} = {
			'parts'			=> $parts,
			'parts_left'	=> $parts_left,
		} ;
	}
	foreach my $err_href (@{$epg_stats->{'errors'}})
	{
		my ($freq, $section, $errors) = @{$err_href}{qw/freq section errors/} ;
		$epg_statistics{'errors'}{$freq}{$section} = $errors ;
	}

prt_data("** EPG STATS ** =", \%epg_statistics) if $DEBUG ;
		
	return (\%epg, \%dates, \%epg_statistics) ;
}


#============================================================================================

=back

=head3 MULTIPLEX RECORDING

=over 4

=cut

#============================================================================================



#----------------------------------------------------------------------------

=item B<add_demux_filter($pid, $pid_type [, $tsid])>

Adds a demultiplexer filter for the specified PID to allow that stream to be recorded.

Internally keeps track of the list of filters created (see L</demux_filter_list()> for format of the
list entries)

$pid_type is a string and should be one of:

	"video"
	"audio"
	"teletext"
	"subtitle"
	"other"

Optionally a tsid may be specified. This will be used if to tune the frontend if it has not yet been tuned.

Returns 0 for success; error code otherwise.

=cut

sub add_demux_filter
{
	my $self = shift ;
	my ($pid, $pid_type, $tsid, $demux_params_href) = @_ ;

printf STDERR "add_demux_filter($pid, $pid_type)\n", $pid if $DEBUG ;

	## valid pid?
	if ( ($pid < 0) || ($pid > $MAX_PID) )
	{
		return $self->handle_error("Invalid PID ($pid)") ;
	}

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	## start with current tuning params
	my $frontend_href = $self->frontend_params() ;
	if (!$frontend_href)
	{
print STDERR " frontend not yet tuned...\n" if $DEBUG >= 5 ;
		## if we've got a tsid, then use that to get the parameters and tune the frontend
		if ($tsid)
		{
print STDERR " + got tsid=$tsid, attempting tune\n" if $DEBUG >= 5 ;
			# ensure we have the tuning info
			my $tuning_href = $self->get_tuning_info() ;
			if (! $tuning_href)
			{
				return $self->handle_error("Unable to get tuning information") ;
			}
			
			# get frontend params
			$frontend_href = Linux::DVB::DVBT::Config::tsid_params($tsid, $tuning_href) ;
			if (! $frontend_href)
			{
				return $self->handle_error("Unable to get frontend parameters for specified TSID ($tsid)") ;
			}
			
			# Tune frontend
			if ($self->set_frontend(%$frontend_href, 'timeout' => $self->timeout))
			{
				return $self->handle_error("Unable to tune frontend") ;
			}
print STDERR " + frontend tuned to tsid=$tsid\n" if $DEBUG >= 5 ;
		}
	}

	## final check
	if (!$frontend_href)
	{
		# Raise an error
		return $self->handle_error("Frontend must be tuned before setting demux filter (have you run scan() yet?)") ;
	}

	## next try setting the filter
	my $fd = dvb_add_demux($self->{dvb}, $pid) ;

	if ($fd <= 0)
	{
		# Raise an error
		return $self->handle_error("Unable to create demux filter for pid $pid") ;
	}

printf STDERR "added demux filter : PID = 0x%03x ( fd = $fd )\n", $pid if $DEBUG ;

	## Create filter information
	if (exists($frontend_href->{'tsid'}))
	{
		# frontend set during normal operation via internal routines
		$tsid = $frontend_href->{'tsid'} ;
	}
	else
	{
		# Someone has called the frontend setup routine directly, so update TSID to match!
		my $tuning_href = $self->get_tuning_info() ;
		$tsid = Linux::DVB::DVBT::Config::find_tsid($frontend_href->{'frequency'}, $tuning_href) ;

		# save tsid
		$frontend_href->{'tsid'} = $tsid ;
	}
	my $filter_href = {
		'fd'		=> $fd,
		'tsid'		=> $tsid,
		'pid'		=> $pid,
		'pidtype'	=> $pid_type,
		
		## keep track of the associated program's demux params  
		'demux_params'	=> $demux_params_href,
	} ;

	push @{$self->{_demux_filters}}, $filter_href ;

	return 0 ;
}


#----------------------------------------------------------------------------

=item B<demux_filter_list()>

Return the list of currently active demux filters.

Each filter entry in the list consists of a HASH ref of the form:

	'fd'		=> file handle for this filter
	'tsid'		=> Transponder ID
	'pid'		=> Stream PID
	'pidtype'	=> $pid_type,

=cut

sub demux_filter_list
{
	my $self = shift ;
	return $self->{_demux_filters} ;
}

#----------------------------------------------------------------------------

=item B<close_demux_filters()>

Closes any currently open demux filters (basically tidies up after finished recording)

=cut

sub close_demux_filters
{
	my $self = shift ;

#prt_data("close_demux_filters() dvb=", $self->{dvb}, "Demux filters=", $self->{_demux_filters}) ;

	# hardware closed?
	unless ($self->dvb_closed())
	{
		foreach my $filter_href (@{$self->{_demux_filters}} )
		{
			dvb_del_demux($self->{dvb}, $filter_href->{fd}) ;
		}
	}
	$self->{_demux_filters} = [] ;
}

#----------------------------------------------------------------------------

=item B<multiplex_close()>

Clears out the list of recordings for a multiplex. Also releases any demux filters.

=cut


# clear down any records
sub multiplex_close
{
	my $self = shift ;

	$self->close_demux_filters() ;
	$self->{_multiplex_info} = {
		'duration' 	=> 0,
		'tsid'	 	=> 0,
		'files'		=> {},
	} ;
}

#----------------------------------------------------------------------------

=item B<multiplex_parse($chan_spec_aref, @args)>

Helper function intended to be used to parse a program's arguments list (@ARGV). The arguments
are parsed into the provided ARRAY ref ($chan_spec_aref) that can then be passed to L</multiplex_select($chan_spec_aref, %options)>
(see that method for a description of the $chan_spec_aref ARRAY).

The arguments define the set of streams (all from the same multiplex, or transponder) that are to be recorded
at the same time into each file. 

Each stream definition must start with a filename, followed by either channel names or pid numbers. Also, 
you must specify the duration of the stream. Finally, an offset time can be specified that delays the start of 
the stream (for example, if the start time of the programs to be recorded are staggered).

A file defined by channel name(s) may optionally also contain a language spec and an output spec: 

The output spec determines which type of streams are included in the recording. By default, "video" and "audio" tracks are recorded. You can
override this by specifying the output spec. For example, if you also want the subtitle track to be recorded, then you need to
specify the output includes video, audio, and subtitles. This can be done either by specifying the types in full or by just their initials.

For example, any of the following specs define video, audio, and subtitles:

	"audio, video, subtitle"
	"a, v, s"
	"avs"

Note that, if the file format explicitly defines the type of streams required, then there is no need to specify an output spec. For example,
specifying that the file format is mp3 will ensure that only the audio is recorded.

In a similar fashion, the language spec determines the audio streams to be recorded in the program. Normally, the default audio stream is included 
in the recorded file. If you want either an alternative audio track, or additional audio tracks, then you use the language spec to 
define them. The spec consists of a space seperated list of language names. If the spec contains a '+' then the audio streams are 
added to the default; otherwise the default audio is B<excluded> and only those other audio tracks in the spec are recorded. Note that
the specification order is important, audio streams from the language spec are matched with the audio details in the specified order. Once a 
stream has been skipped there is no back tracking (see the examples below for clarification).

For example, if a channel has the audio details: eng:601 eng:602 fra:603 deu:604 (i.e. 2 English tracks, 1 French track, 1 German) then

=over 4

=item lang="+eng"

Results in the default audio (pid 601) and the next english track (pid 602) recorded

=item lang="fra"

Results in just the french track (pid 603) recorded

=item lang="eng fra"

Results in the B<second> english (pid 602) and the french track (pid 603) recorded

=item lang="fra eng"

Results in an error. The english tracks have already been skipped to match the french track, and so will not be matched again.

=back

Note that the output spec overrides the language spec. If the output does not include audio, then the language spec is ignored.


Example valid sets of arguments are:

=over 4

=item file=f1.mpeg chan=bbc1 out=avs lang=+eng len=1:00 off=0:10

Record channel BBC1 into file f1.mpeg, include subtitles, add second English audio track, record for 1 hour, start recording 10 minutes from now

=item file=f2.mp3 chan=bbc2 len=0:30

Record channel BBC2 into file f2.mp3, audio only, record for 30 minutes

=item file=f3.ts pid=600 pid=601 len=0:30

Record pids 600 & 601 into file f3.ts, record for 30 minutes

=back

=cut

my %multiplex_params = (
	'^f'				=> 'file',
	'^c'				=> 'chan',
	'^p'				=> 'pid',
	'^lan'				=> 'lang',
	'^out'				=> 'out',
	'^(len|duration)'	=> 'duration',
	'^off'				=> 'offset',
	'^title'			=> 'title',
) ;
sub multiplex_parse
{
	my $self = shift ;
	my ($chan_spec_aref, @args) = @_ ;

	## work through the args
	my $current_file_href ;
	my $current_chan_href ;
	foreach my $arg (@args)
	{
		## skip non-valid
		
		# strip off any extra quotes
		if ($arg =~ /(\S+)\s*=\s*([\'\"]{0,1})([^\2]*)\2/)
		{
			my ($var, $value, $valid) = (lc $1, $3, 0) ;

			# allow fuzzy input - convert to known variable names
			foreach my $regexp (keys %multiplex_params)
			{
				if ($var =~ /$regexp/)
				{
					$var = $multiplex_params{$regexp} ;
					++$valid ;
					last ;
				}
			}
			
			# check we know this var
			if (!$valid)
			{
				return $self->handle_error("Unexpected variable \"$var = $value\"") ;
			}
			
			# new file
			if ($var eq 'file')
			{
				$current_chan_href = undef ;
				$current_file_href = {
					'file'		=> $value,
					'chans'		=> [],
					'pids'		=> [],
				} ;
				push @$chan_spec_aref, $current_file_href ;
				next ;
			}
			else
			{
				# check file has been set before moving on
				return $self->handle_error("Variable \"$var = $value\" defined before specifying the filename") 
					unless defined($current_file_href) ;
			}

			# duration / offset
			my $handled ;
			foreach my $genvar (qw/duration offset/)
			{
				if ($var eq $genvar)
				{
					$current_file_href->{$genvar} = $value ;
					++$handled ;
					last ;
				}
			}
			next if $handled ;
			
			# new pid
			if ($var eq 'pid')
			{
				push @{$current_file_href->{'pids'}}, $value ;
				next ;
			}
			
			# new chan
			if ($var eq 'chan')
			{
				$current_chan_href = {
					'chan'	=> $value,
				} ;
				push @{$current_file_href->{'chans'}}, $current_chan_href ;
				next ;
			}
			else
			{
				# check chan has been set before moving on
				return $self->handle_error("Variable \"$var = $value\" defined before specifying the channel") 
					unless defined($current_chan_href) ;
			}
			
			# lang / out - requires chan
			foreach my $chvar (qw/lang out/)
			{
				if ($var eq $chvar)
				{
					$current_chan_href->{$chvar} = $value ;
					last ;
				}
			}
			
		}
		else
		{
			return $self->handle_error("Unexpected arg \"$arg\"") ;
		}
	}	
	
	## Check entries for required information
	foreach my $spec_href (@$chan_spec_aref)
	{
		my $file = $spec_href->{'file'} ;
		if (!$spec_href->{'duration'})
		{
			return $self->handle_error("File \"$file\" has no duration specified") ;
		}
		if (! @{$spec_href->{'pids'}} && ! @{$spec_href->{'chans'}})
		{
			return $self->handle_error("File \"$file\" has no channels/pids specified") ;
		}
		if (@{$spec_href->{'pids'}} && @{$spec_href->{'chans'}})
		{
			return $self->handle_error("File \"$file\" has both channels and pids specified at the same time") ;
		}
	}
		
	return 0 ;
}

#----------------------------------------------------------------------------

=item B<multiplex_select($chan_spec_aref, %options)>

Selects a set of streams based on the definitions in the chan spec ARRAY ref. The array 
contains hashes of:

	{
		'file'		=> filename
		'chans'		=> [ 
			{ 'chan' => channel name, 'lang' => lang spec, 'out' => output },
			... 
		]
		'pids'		=> [ stream pid, ... ]
		'offset'	=> time
		'duration'	=> time
	}

Each entry must contain a target filename, a recording duration, and either channel definitions or pid definitions.
The channel definition list consists of HASHes containing a channel name, a language spec, and an output spec. 

The language and output specs are as described in L</multiplex_parse($chan_spec_aref, @args)>

The optional options hash consists of:

	{
		'tsid'			=> tsid
		'lang'			=> default lang spec
		'out'			=> default output spec
		'no-pid-check'	=> when set, allows specification of any pids
	}

The TSID definition defines the transponder (multiplex) to use. Use this when pids define the streams rather than 
channel names and the pid value(s) may occur in multiple TSIDs.

If you define default language or output specs, these will be used in all file definitions unless that file definition
has it's own output/language spec. For example, if you want all files to include subtitles you can specify it once as
the default rather than for every file.

The method sets up the DVB demux filters to record each of the required streams. It also sets up a HASH of the settings,
which may be read using L</multiplex_info()>. This hash being used in L</multiplex_record(%multiplex_info)>.

Setting the 'no-pid-check' allows the recording of pids that are not known to the module (i.e. not in the scan files). This is
for experimental use.

=cut


sub multiplex_select
{
	my $self = shift ;
	my ($chan_spec_aref, %options) = @_ ;
	
	my $error = 0 ;

print STDERR "multiplex_select()\n" if $DEBUG>=10 ;

	## ensure we have the tuning info
	my $tuning_href = $self->get_tuning_info() ;
	if (! $tuning_href)
	{
		return $self->handle_error("Unable to get tuning information from config file (have you run scan() yet?)") ;
	}

	# hardware closed?
	if ($self->dvb_closed())
	{
		# Raise an error
		return $self->handle_error("DVB tuner has been closed") ;
	}

	## start with clean slate
	$self->multiplex_close() ;	

	my %files ;

	## Defaults
	my $def_lang = $options{'lang'} || "" ;
	my $def_out = $options{'out'} || "" ;

	## start with TSID option
	my $tsid = $options{'tsid'} ;
	
	## process each entry
	foreach my $spec_href (@$chan_spec_aref)
	{
		my $file = $spec_href->{'file'} ;
		if ($file)
		{
			## get entry for this file (or create it)
			my $href = $self->_multiplex_file_href($file) ;
			
			# keep track of file settings
			$files{$file} ||= {'chans'=>0, 'pids'=>0} ;

			# add error if already got pids for this file
			if ( $files{$file}{'pids'} )
			{
				return $self->handle_error("Cannot mix chan definitions with pid definitions for file \"$file\"") ;
			}

			# set time
			$href->{'offset'} ||= Linux::DVB::DVBT::Utils::time2secs($spec_href->{'offset'} || 0) ;
			$href->{'duration'} ||= Linux::DVB::DVBT::Utils::time2secs($spec_href->{'duration'} || 0) ;

			# beta: title
			$href->{'title'} ||= $spec_href->{'title'} ;
			
			# calc total length
			my $period = $href->{'offset'} + $href->{'duration'} ;
			$self->{_multiplex_info}{'duration'}=$period if ($self->{_multiplex_info}{'duration'} < $period) ;
			
			# chans
			$spec_href->{'chans'} ||= [] ;
			foreach my $chan_href (@{$spec_href->{'chans'}})
			{
				my $channel_name = $chan_href->{'chan'} ;
				my $lang = $chan_href->{'lang'}  || $def_lang ;
				my $out = $chan_href->{'out'} || $def_out ;
				
				# find channel
				my ($frontend_params_href, $demux_params_href) = Linux::DVB::DVBT::Config::find_channel($channel_name, $tuning_href) ;
				if (! $frontend_params_href)
				{
					return $self->handle_error("Unable to find channel $channel_name") ;
				}

				# check in same multiplex
				$tsid ||= $frontend_params_href->{'tsid'} ;
				if ($tsid != $frontend_params_href->{'tsid'})
				{
					return $self->handle_error("Channel $channel_name (on $frontend_params_href->{'tsid'}) is not in the same multiplex as other channels/pids (on $tsid)") ;
				}
				
				# Ensure the combination of file format, output spec, and language spec are valid. They get adjusted as required
				my $dest_file = $file ;
				$error = Linux::DVB::DVBT::Ffmpeg::sanitise_options(\$dest_file, \$out, \$lang,
					$href->{'errors'}, $href->{'warnings'}) ;
				return $self->handle_error($error) if $error ;

				# save settings
				$href->{'dest_file'} = $dest_file ;
				$href->{'out'} = $out ;
				$href->{'lang'} = $lang ;

				# Handle output specification to get a list of pids
				my @pids ;
				$error = Linux::DVB::DVBT::Config::out_pids($demux_params_href, $out, $lang, \@pids) ;
				return $self->handle_error($error) if $error ;

prt_data(" + Add pids for chan = ", \@pids) if $DEBUG >= 15 ;
				
				# add filters
				foreach my $pid_href (@pids)
				{
					# add filter
					$error = $self->add_demux_filter($pid_href->{'pid'}, $pid_href->{'pidtype'}, $tsid, $pid_href->{'demux_params'}) ;
					return $self->handle_error($error) if $error ;
					
					# keep demux filter info
					push @{$href->{'demux'}}, $self->{_demux_filters}[-1] ;
					
					++$files{$file}{'chans'} ;
				}
			}
			

			# pids
			$spec_href->{'pids'} ||= [] ;
			foreach my $pid (@{$spec_href->{'pids'}})
			{
				# add error if already got pids for this file
				if ( $files{$file}{'chans'} )
				{
					return $self->handle_error("Cannot mix chan definitions with pid definitions for file \"$file\"") ;
				}

				# array of: { 'pidtype'=>$type, 'tsid' => $tsid, ... } for this pid value
				my $pid_href ;
				my @pid_info = Linux::DVB::DVBT::Config::pid_info($pid, $tuning_href) ;

				if (!@pid_info)
				{
					# can't find pid - see if it's a standard SI table
					my $new_pid_href = $self->_si_pid($pid, $tsid) ;
					push @pid_info, $new_pid_href if $new_pid_href ;
				}
				if (! @pid_info)
				{
					# can't find pid
					if ($options{'no-pid-check'})
					{
						# create a simple entry if we allow any pids
						$pid_href = {
							'pidtype' 	=> 'data',
							'tsid'	=> $tsid,
						} ;
					}
					else
					{
						return $self->handle_error("Unable to find PID $pid in the known list stored in your config file") ;
					}
				}
				elsif (@pid_info > 1)
				{
					# if we haven't already got a tsid, use the first
					if (!$tsid)
					{
						$pid_href = $pid_info[0] ;
					}
					else
					{
						# find entry with matching TSID
						foreach (@pid_info)
						{
							if ($_->{'tsid'} == $tsid)
							{
								$pid_href = $_ ;
								last ;
							}
						}
					}

					# error if none match
					if (!$pid_href)
					{
						return $self->handle_error("Multiple multiplexes contain pid $pid, please specify the multiplex number (tsid)") ;
					}
				}
				else
				{
					# found a single one
					$pid_href = $pid_info[0] ;
				}
				
				# set filter
				if ($pid_href)
				{
prt_data(" + Add pid = ", $pid_href) if $DEBUG >= 15 ;

					# check multiplex
					$tsid ||= $pid_href->{'tsid'} ;
					if (!defined($tsid) || !defined($pid_href->{'tsid'}) || ($tsid != $pid_href->{'tsid'}) )
					{
						return $self->handle_error("PID $pid (on $pid_href->{'tsid'}) is not in the same multiplex as other channels/pids (on $tsid)") ;
					}
					
					# add a filter
					$error = $self->add_demux_filter($pid, $pid_href->{'pidtype'}, $tsid, $pid_href->{'demux_params'}) ;
					return $self->handle_error($error) if $error ;
					
					# keep demux filter info
					push @{$href->{'demux'}}, $self->{_demux_filters}[-1] ;
					
					$files{$file}{'pids'}++ ;
				}
			}
		}		
	}
	
	## Add in SI tables (if required) to the multiplex info
	$error = $self->_add_required_si($tsid) ;
	
	## ensure pid lists match the demux list
	$self->_update_multiplex_info($tsid) ;

	return $error ;
}	

#----------------------------------------------------------------------------

=item B<multiplex_record_duration()>

Returns the total recording duration (in seconds) of the currently spricied multiplex recordings.

Used for informational purposes.

=cut

sub multiplex_record_duration
{
	my $self = shift ;
	
	return $self->{_multiplex_info}{'duration'} ;
}

#----------------------------------------------------------------------------

=item B<multiplex_info()>

Returns HASH of the currently defined multiplex filters. HASH is of the form:

  files => {
	$file => {
		'pids'	=> [
			{
				'pid'	=> Stream PID
				'pidtype'	=> pid type (i.e. 'audio', 'video', 'subtitle')
			},
			...
		]
		'offset' => offset time for this file
		'duration' => duration for this file

		'destfile'	=> final written file name (set by L</multiplex_transcode(%multiplex_info)>)
		'warnings'	=> [
			ARRAY ref of list of warnings (set by L</multiplex_transcode(%multiplex_info)>)
		],
		'errors'	=> [
			ARRAY ref of list of errors (set by L</multiplex_transcode(%multiplex_info)>)
		],
		'lines'	=> [
			ARRAY ref of lines of output from the transcode/demux operation(s) (set by L</multiplex_transcode(%multiplex_info)>)
		],
	},
  },
  duration => maximum recording duration in seconds
  tsid => the multiplex id

where there is an entry for each file, each entry containing a recording duration (in seconds),
an offset time (in seconds), and an array of pids that define the streams required for the file.

=cut

sub multiplex_info
{
	my $self = shift ;
	
	return %{$self->{_multiplex_info}} ;
}

#----------------------------------------------------------------------------

=item B<multiplex_record(%multiplex_info)>

Records the selected streams into their files. Note that the recorded files will
be the specified name, but with the extension set to '.ts'. You can optionally then
call L</multiplex_transcode(%multiplex_info)> to transcode the files into the requested file format.

=cut

sub multiplex_record
{
	my $self = shift ;
	my (%multiplex_info) = @_ ;
	
	my $error = 0 ;

Linux::DVB::DVBT::prt_data("multiplex_record() : multiplex_info=", \%multiplex_info) if $DEBUG>=10 ;

	# process information ready for C code 
	my @multiplex_info ;
	foreach my $file (keys %{$multiplex_info{'files'}} )
	{
		my $href = {
			'_file'		=> $file,
			'pids'		=> [],
			'errors'	=> {},
		} ;

		# copy scalars
		foreach (qw/offset duration destfile/)
		{
			$href->{$_} = $multiplex_info{'files'}{$file}{$_} ;
		}
		
		# placeholder in case we need to record to intermediate .ts file
		$multiplex_info{'files'}{$file}{'tsfile'} = "" ;
		
		# if file type is .ts, then leave everything; otherwise save the requested file name
		# and change source filename to .ts
		my ($name, $destdir, $suffix) = fileparse($multiplex_info{'files'}{$file}{'destfile'}, '\..*');
print STDERR " + dest=$multiplex_info{'files'}{$file}{'destfile'} : name=$name dir=$destdir ext=$suffix\n" if $DEBUG>=10 ;
		if (lc $suffix ne '.ts')
		{
			# modify destination so that we record to it
			$href->{'destfile'} = "$destdir$name.ts" ;
			
			# report intermediate file
			$multiplex_info{'files'}{$file}{'tsfile'} = "$destdir$name.ts" ;

print STDERR " + + mod extension\n" if $DEBUG>=10 ;
		}

		# fill in the pid info
		foreach my $pid_href (@{$multiplex_info{'files'}{$file}{'pids'}})
		{
			my $pid = $pid_href->{'pid'} ;
			push @{$href->{'pids'}}, $pid ;
			
			$href->{'errors'}{$pid} = 0 ;
			$href->{'pkts'}{$pid} = 0 ;
		}
		push @multiplex_info, $href ;
		
		# check directory exists
		if (! -d $destdir) 
		{
			mkpath([$destdir], $DEBUG, 0755) or return $self->handle_error("Error: unable to create directory \"$destdir\" : $!") ;
		}
		
		# make sure we can write file
		my $destfile = $href->{'destfile'} ;
		open my $fh, ">$destfile" or return $self->handle_error("Error: unable to write to file \"$destfile\" : $!") ;
		close $fh ;
	}

Linux::DVB::DVBT::prt_data(" + info=", \@multiplex_info) if $DEBUG>=10 ;

	## @multiplex_info = (
	#		{
	#			destfile	=> recorded ts file
	#			pids		=> [
	#				pid,
	#				pid,
	#				...
	#			]
	#			
	#		}
	#	
	#	)

	## do the recordings
	$error = dvb_record_demux($self->{dvb}, \@multiplex_info) ;
	return $self->handle_error(dvb_error_str()) if $error ;

Linux::DVB::DVBT::prt_data(" + returned info=", \@multiplex_info) if $DEBUG ;
	
	## Pass error counts back
	## @multiplex_info = (
	#		{
	#			destfile	=> recorded ts file
	#			pids		=> [
	#				pid1,
	#				pid2,
	#				...
	#			],
	#			errors		=> {
	#				pid1	=> error_count1,
	#				pid2	=> error_count2,
	#				...
	#			}
	#			pkts		=> {
	#				pid1	=> packet_count1,
	#				pid2	=> packet_count2,
	#				...
	#			}
	#			
	#		}
	#	
	#	)
	foreach my $href (@multiplex_info)
	{
Linux::DVB::DVBT::prt_data(" + + href=", $href) if $DEBUG ;
		my $file = $href->{'_file'} ;
		#files => {
		#	$file => {
		#		'pids'	=> [
		#			{
		#				'pid'	=> Stream PID
		#				'pidtype'	=> pid type (i.e. 'audio', 'video', 'subtitle')
		#			},
		#			...
		#		]
		foreach my $pid_href (@{$multiplex_info{'files'}{$file}{'pids'}})
		{
			my $pid = $pid_href->{'pid'} ;
#print STDERR " - PID $pid (file=$file)\n" ;
			$pid_href->{'pkts'} = 0 ;
			$pid_href->{'error'} = 0 ;
			if (exists($href->{'errors'}{$pid}))
			{
				$pid_href->{'errors'} = $href->{'errors'}{$pid} ;
#print STDERR " - - errors = $href->{'errors'}{$pid}\n" ;
			}
			if (exists($href->{'pkts'}{$pid}))
			{
				$pid_href->{'pkts'} = $href->{'pkts'}{$pid} ;
#print STDERR " - - pkts = $href->{'pkts'}{$pid}\n" ;
			}
		}
	}
	
	return $error ;
}


#----------------------------------------------------------------------------

=item B<multiplex_transcode(%multiplex_info)>

Transcodes the recorded files into the requested formats (uses ffmpeg helper module).

Sets the following fields in the %multiplex_info HASH:

	$file => {

		...

		'destfile'	=> final written file name
		'warnings'	=> [
			ARRAY ref of list of warnings
		],
		'errors'	=> [
			ARRAY ref of list of errors
		],
		'lines'	=> [
			ARRAY ref of lines of output from the transcode/demux operation(s)
		],
	}

See L<Linux::DVB::DVBT::Ffmpeg::ts_transcode()|Ffmpeg::ts_transcode($srcfile, $destfile, $multiplex_info_href, [$written_files_href])> for further details.

=cut

sub multiplex_transcode
{
	my $self = shift ;
	my (%multiplex_info) = @_ ;

Linux::DVB::DVBT::prt_data("multiplex_transcode() : multiplex_info=", \%multiplex_info) if $DEBUG>=10 ;
	
	my $error = 0 ;
	my @errors ;
	
	## keep track of each filename as it is written, so we don't overwrite anything
	my %written_files ;
	
	## process each file
	foreach my $file (keys %{$multiplex_info{'files'}})
	{
Linux::DVB::DVBT::prt_data("Call ts_transcode for file=$file with : info=", $multiplex_info{'files'}{$file}) if $DEBUG>=10 ;

		# run ffmpeg (or just do video duration check)
		$error = Linux::DVB::DVBT::Ffmpeg::ts_transcode(
#			$multiplex_info{'files'}{$file}{'destfile'}, 
#			$multiplex_info{'files'}{$file}{'_destfile'}, 
			$multiplex_info{'files'}{$file}{'tsfile'}, 
			$multiplex_info{'files'}{$file}{'destfile'}, 
			$multiplex_info{'files'}{$file}, 
			\%written_files) ;
		
		# collect all errors together
		if ($error)
		{
			push @errors, "FILE: $file" ;
			push @errors, @{$multiplex_info{'files'}{$file}{'errors'}} ;
		}
	}
	
	# handle all errors in one go
	if (@errors)
	{
		$error = join "\n", @errors ;
		return $self->handle_error($error) ;
	}
	return $error ;
}



#============================================================================================

=back

=head3 DEBUG UTILITIES

=over 4

=cut

#============================================================================================


=item B<prt_data(@list)>

Print out each item in the list, showing HASH hierarchies. Handles scalars, 
hashes (as an array), arrays, ref to scalar, ref to hash, ref to array, object.

Useful for debugging.

=cut


#=====================================================================
# MODULE USAGE
#=====================================================================
#


#---------------------------------------------------------------------
sub _setup_modules
{
	# Attempt to load Debug object
	if (_load_module('Debug::DumpObj'))
	{
		# Create local function
		*prt_data = sub {print STDERR Debug::DumpObj::prtstr_data(@_)} ;
	}
	else
	{
		# See if we've got Data Dummper
		if (_load_module('Data::Dumper'))
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
sub _load_module
{
	my ($mod) = @_ ;
	
	my $ok = 1 ;

	# see if we can load up the package
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


# ============================================================================================
BEGIN {
	# Debug only
	_setup_modules() ;
}


#============================================================================================

=back

=head3 INTERNAL METHODS

=over 4

=cut

#============================================================================================


#-----------------------------------------------------------------------------

=item B<hwinit()>

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

#----------------------------------------------------------------------------

=item B<log_error($error_message)>

I<Object internal method>

Add the error message to the error log. Get the log as an ARRAY ref via the 'errors()' method

=cut

sub log_error
{
	my $self = shift ;
	my ($error_message) = @_ ;
	
	push @{$self->errors()}, $error_message ;
	
}

#-----------------------------------------------------------------------------

=item B<dvb_closed()>

Returns true if the DVB tuner has been closed (or failed to open).

=cut

sub dvb_closed
{
	my $self = shift ;

	return !$self->{dvb} ;
}


#-----------------------------------------------------------------------------
# return current (or create new) file entry in multiplex_info
sub _multiplex_file_href
{
	my $self = shift ;
	my ($file) = @_ ;
	
	$self->{_multiplex_info}{'files'}{$file} ||= {

		# start with this being the same as the requested filename
		'destfile'	=> $file,
		
		# init
		'offset' 	=> 0,
		'duration' 	=> 0,
		'title' 	=> '',
		'warnings'	=> [],
		'errors'	=> [],
		'lines'		=> [],
		'demux'		=> [],

		# beta: title
		'title' 	=> '',
	} ;
	my $href = $self->{_multiplex_info}{'files'}{$file} ;

	return $href ;
}

#-----------------------------------------------------------------------------
# Add in the required SI tables to any recording that requires it OR if the 'add_si'
# option is set
sub _add_required_si
{
	my $self = shift ;
	my ($tsid) = @_ ;
	my $error ;

	# get flag
	my $force_si = $self->{'add_si'} ;

	# set tsid if not already set
	$self->{_multiplex_info}{'tsid'} ||= $tsid ;

print STDERR "_add_required_si(tsid=$tsid, force=$force_si)\n" if $DEBUG>=10 ;
prt_data("current mux info=", $self->{_multiplex_info}) if $DEBUG>=15 ;
	
	foreach my $file (keys %{$self->{_multiplex_info}{'files'}})
	{
		my $add_si = $force_si ;

		## get entry for this file (or create it)
		my $href = $self->_multiplex_file_href($file) ;
		
		## check pids looking for non-audio/video (get pnr for later)
		my $demux_params_href ;
		my %pids ;
		foreach my $demux_href (@{$self->{_multiplex_info}{'files'}{$file}{'demux'}})
		{
			# keep track of the pids scheduled
			++$pids{ $demux_href->{'pid'} } ;
			
			# get HASH ref to program's demux params
			$demux_params_href = $demux_href->{'demux_params'} if ($demux_href->{'demux_params'}) ;

			# see if non-av
			if ( ($demux_href->{'pidtype'} ne 'audio') && ($demux_href->{'pidtype'} ne 'video') )
			{
				++$add_si ;
			}
		}

		my $pmt = $demux_params_href->{'pmt'} ;
		my $pcr = $demux_params_href->{'pcr'} ;
print STDERR " + file=$file : add=$add_si  pmt=$pmt  pcr=$pcr\n" if $DEBUG>=10 ;
prt_data("demux_params_href=", $demux_params_href) if $DEBUG>=10 ;
prt_data("scheduled PIDS==", \%pids) if $DEBUG>=10 ;

		## Add tables if necessary (and possible!)
		if ($add_si)
		{
			if (!$pmt)
			{
				$error = "Unable to determine PMT pid (have you re-scanned with this latest version?)" ;
				return $self->handle_error($error) ;
			}
			else
			{
				foreach my $pid_href (
					{ 'pidtype' => 'PAT',	'pid' => $SI_TABLES{'PAT'}, },
#					{ 'pidtype' => 'SDT',	'pid' => $SI_TABLES{'SDT'}, },
#					{ 'pidtype' => 'TDT',	'pid' => $SI_TABLES{'TDT'}, },
					{ 'pidtype' => 'PMT',	'pid' => $pmt, },
					{ 'pidtype' => 'PCR',	'pid' => $pcr, },
				)
				{
print STDERR " + pid=$pid_href->{'pid'} pidtype=$pid_href->{'pidtype'}\n" if $DEBUG>=10 ;

					# skip any already scheduled
					next unless defined($pid_href->{'pid'}) ;
					next if exists($pids{ $pid_href->{'pid'} }) ;
					
print STDERR " + check defined..\n" if $DEBUG>=10 ;
					next unless defined($pid_href->{'pid'}) ;

print STDERR " + add filter..\n" if $DEBUG>=10 ;
					
					# add filter
					$error = $self->add_demux_filter($pid_href->{'pid'}, $pid_href->{'pidtype'}, $tsid, $demux_params_href) ;
					return $self->handle_error($error) if $error ;
					
					# keep demux filter info
					push @{$href->{'demux'}}, $self->{_demux_filters}[-1] ;
				}
			}
		}
	}

prt_data("final mux info=", $self->{_multiplex_info}) if $DEBUG>=15 ;
	
	return $error ;
}


#-----------------------------------------------------------------------------
# Ensure that the multiplex_info HASH is up to date (pids match the demux list)
sub _update_multiplex_info
{
	my $self = shift ;
	my ($tsid) = @_ ;

	$self->{_multiplex_info}{'tsid'} ||= $tsid ;
	
	foreach my $file (keys %{$self->{_multiplex_info}{'files'}})
	{
		$self->{_multiplex_info}{'files'}{$file}{'pids'} = [] ;
		
		# fill in the pid info
		foreach my $demux_href (@{$self->{_multiplex_info}{'files'}{$file}{'demux'}})
		{
			push @{$self->{_multiplex_info}{'files'}{$file}{'pids'}}, {
				'pid'	=> $demux_href->{'pid'},
				'pidtype'	=> $demux_href->{'pidtype'},
			} ;
		}
	}
}

#-----------------------------------------------------------------------------
# Check to see if pid is an SI table
sub _si_pid
{
	my $self = shift ;
	my ($pid, $tsid, $pmt) = @_ ;
	my $pid_href ;

	# check for SI
	if (exists($SI_LOOKUP{$pid}))
	{
		$pid_href = {
			'tsid'	=> $tsid,
			'pidtype'	=> $SI_LOOKUP{$pid},
			'pmt'	=> 1,
		} ;
	}

	
	# if not found & pnr specified, see if it's PMT
	if (!$pid_href && $pmt)
	{
		$pid_href = {
			'tsid'	=> $tsid,
			'pidtype'	=> 'PMT',
			'pmt'	=> $pmt,
		} ;
	}

	return $pid_href ;
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

None that I know of!

=head1 FEATURES

The current release supports:

=over 4

=item *

Tuning to a channel based on "fuzzy" channel name (i.e. you can specify a channel with/without spaces, in any case, and with
numerals or number names)  

=item *

Transport stream recording (i.e. program record) with large file support

=item *

Electronic program guide. Builds the TV/radio listings as a HASH structure (which you can then store into a database, file etc and use
to schedule your recordings)

=item *

Option to record all/any of the audio streams for a program (e.g. allows for descriptive audio for visually impaired)

=item *

Recording of any streams within a multiplex at the same time (i.e. multi-channel recording using a single DVB device)

=item *

Additional module providing wrappers to ffmpeg as "helper" programs to transcode recorded files (either during "normal" or "multiplex" recording). 

=back


=head1 FUTURE

Subsequent releases will include:

=over 4

=item *

I'm looking into the option of writing the files directly as mpeg. Assuming I can work my way through the mpeg2 specification! 

=item *

Support for event-driven applications (e.g. POE). I need to re-write some of the C to allow for event-driven hooks (and special select calls)

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Steve Price

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

