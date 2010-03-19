#!perl

use strict;
use warnings;
use Test::More ;

use Linux::DVB::DVBT ;
use Linux::DVB::DVBT::Config ;

#$Linux::DVB::DVBT::Conf::DEBUG = 15 ;

#[4107-4171]
#video = 600
#lcn = 1
#tsid = 4107
#name = BBC ONE
#ca = 0
#net = BBC
#audio = 601
#teletext = 0
#subtitle = 605
#type = 1
#pnr = 4171
#audio_details = eng:601 eng:602 fra:9999 deu:9900

my @tests = (
	{
		'out'	=> "avs",
		'lang'	=> "",
		'audio_pids'	=> 
			[ 601,  ],
		'out_pids'	=> 
			[
				{
					'pid' => 601,
					'type' => 'audio',
				},
				{
					'pid' => 600,
					'type' => 'video',
				},
				{
					'pid' => 605,
					'type' => 'subtitle',
				},
			],
	},
	{
		'out'	=> "av",
		'lang'	=> "+eng",
		'audio_pids'	=> 
			[ 601, 602,  ],
		'out_pids'	=> 
			[
				{
					'pid' => 601,
					'type' => 'audio',
				},
				{
					'pid' => 602,
					'type' => 'audio',
				},
				{
					'pid' => 600,
					'type' => 'video',
				},
			],
	},
	{
		'out'	=> "a",
		'lang'	=> "eng",
		'audio_pids'	=> 
			[ 602,  ],
		'out_pids'	=> 
			[
				{
					'pid' => 602,
					'type' => 'audio',
				},
			],
	},
	{
		'out'	=> "",
		'lang'	=> "fra",
		'audio_pids'	=> 
			[ 9999,  ],
		'out_pids'	=> 
			[
				{
					'pid' => 9999,
					'type' => 'audio',
				},
				{
					'pid' => 600,
					'type' => 'video',
				},
			],
	},
	{
		'out'	=> "a",
		'lang'	=> "eng eng",
		'error'	=> 1,
		'audio_pids'	=> 
			[ 602,  ],
		'out_pids'	=> 
			[
			],
	},
	{
		'out'	=> "",
		'lang'	=> "ita",
		'error'	=> 1,
		'audio_pids'	=> 
			[  ],
		'out_pids'	=> 
			[
			],
	},
	{
		'out'	=> "",
		'lang'	=> "fra eng",
		'error'	=> 1,
		'audio_pids'	=> 
			[ 9999,  ],
		'out_pids'	=> 
			[
			],
	},
	{
		'out'	=> "",
		'lang'	=> "fra eng deu",
		'error'	=> 1,
		'audio_pids'	=> 
			[ 9999, ],
		'out_pids'	=> 
			[
			],
	},
);

plan tests => scalar(@tests) * 2 * 2 ;

	## Create object
	my $dvb = Linux::DVB::DVBT->new(
		'dvb' => 1,		# special case to allow for testing
		
		'adapter_num'	=> 1,
		'frontend_num'	=> 0,
		
		'frontend_name'	=> '/dev/dvb/adapter1/frontend0',
		'demux_name'	=> '/dev/dvb/adapter1/demux0',
		'dvr_name'	=> '/dev/dvb/adapter1/dvr0',
		
	) ;
	
	$dvb->config_path('./t/config-ox') ;
	my $tuning_href = $dvb->get_tuning_info() ;
	
	my $out  ;
	my $lang ;
	my $channel_name = "bbc1" ;

	# find channel
	my ($frontend_params_href, $demux_params_href) = Linux::DVB::DVBT::Config::find_channel($channel_name, $tuning_href) ;
	if (! $frontend_params_href)
	{
		die "unable to find $channel_name" ;
	}

	foreach my $href (@tests)
	{
		test_audio($demux_params_href, $href->{'lang'}, $href->{'audio_pids'}, $href->{'error'}||0) ;
		test_out($demux_params_href, $href->{'out'}, $href->{'lang'}, $href->{'out_pids'}, $href->{'error'}||0) ;
	}
	exit 0 ;

#------------------------------------------------------------------------------------------------
sub test_audio
{
	my ($demux_params_href, $lang, $expected_aref, $expect_error) = @_ ;

	my @pids ;
	my $error ; 

	$error = Linux::DVB::DVBT::Config::audio_pids($demux_params_href, $lang, \@pids) ;
	is_deeply(\@pids, $expected_aref, "Audio pids lang=\"$lang\" ") ;
	is( $error?1:0, $expect_error, "Audio error lang=\"$lang\" ") ;

}
	
#------------------------------------------------------------------------------------------------
sub test_out
{
	my ($demux_params_href, $out, $lang, $expected_aref, $expect_error) = @_ ;

	my @pids ;
	my $error ; 
	
	$error = Linux::DVB::DVBT::Config::out_pids($demux_params_href, $out, $lang, \@pids) ;
	is_deeply(\@pids, $expected_aref, "Output spec pids lang=\"$lang\" out=\"$out\"") ;
	is( $error?1:0, $expect_error, "Output spec error lang=\"$lang\" out=\"$out\" ") ;
}
	
__END__

