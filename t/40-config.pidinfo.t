#!perl

use strict;
use warnings;
use Test::More ;

use Linux::DVB::DVBT ;
use Linux::DVB::DVBT::Config ;

#$Linux::DVB::DVBT::Conf::DEBUG = 15 ;

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
	
	my $pid ;

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
#audio_details = eng:601 eng:602 fra:9999
#
#[12290-14272]
#video = 6273
#tsid = 12290
#lcn = 23
#name = bid tv
#ca = 0
#net = Sit-Up Ltd
#audio = 6274
#teletext = 8888
#subtitle = 0
#type = 1
#pnr = 14272
#audio_details = eng:6274 fra:9999 deu:9900

my @tests = (
	{
		'pid'	=> 600,
		'pids'	=> [
			{
				'video'	=> '600',
				'tsid'	=> '8199',
				'lcn'	=> '33',
				'name'	=> 'ITV2 +1',
				'ca'	=> '0',
				'net'	=> 'ITV',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '603',
				'type'	=> 'video',
				'pnr'	=> '8362',
				'audio_details'	=> 'eng:601 eng:602',
			},
			{
				'video'	=> '600',
				'tsid'	=> '4107',
				'lcn'	=> '1',
				'name'	=> 'BBC ONE',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'video',
				'pnr'	=> '4171',
				'audio_details'	=> 'eng:601 eng:602 fra:9999 deu:9900',
			},
		],
	},
	{
		'pid'	=> 601,
		'pids'	=> [
			{
				'video'	=> '601',
				'tsid'	=> '24576',
				'lcn'	=> '24',
				'name'	=> 'ITV4',
				'ca'	=> '0',
				'net'	=> 'ITV',
				'audio'	=> '602',
				'teletext'	=> '0',
				'subtitle'	=> '603',
				'type'	=> 'video',
				'pnr'	=> '28032',
				'audio_details'	=> 'eng:602 eng:604',
			},
			{
				'video'	=> '201',
				'tsid'	=> '16384',
				'lcn'	=> '71',
				'name'	=> 'CBeebies',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '401',
				'teletext'	=> '0',
				'subtitle'	=> '601',
				'type'	=> 'subtitle',
				'pnr'	=> '16960',
				'audio_details'	=> 'eng:401 eng:402',
			},
			{
				'video'	=> '600',
				'tsid'	=> '8199',
				'lcn'	=> '33',
				'name'	=> 'ITV2 +1',
				'ca'	=> '0',
				'net'	=> 'ITV',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '603',
				'type'	=> 'audio',
				'pnr'	=> '8362',
				'audio_details'	=> 'eng:601 eng:602',
			},
			{
				'video'	=> '600',
				'tsid'	=> '4107',
				'lcn'	=> '1',
				'name'	=> 'BBC ONE',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'audio',
				'pnr'	=> '4171',
				'audio_details'	=> 'eng:601 eng:602 fra:9999 deu:9900',
			},
		],
	},
	{
		'pid'	=> 605,
		'pids'	=> [
			{
				'video'	=> '600',
				'tsid'	=> '4107',
				'lcn'	=> '1',
				'name'	=> 'BBC ONE',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'subtitle',
				'pnr'	=> '4171',
				'audio_details'	=> 'eng:601 eng:602 fra:9999 deu:9900',
			},
			{
				'video'	=> '205',
				'tsid'	=> '16384',
				'lcn'	=> '81',
				'name'	=> 'BBC Parliament',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '421',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'subtitle',
				'pnr'	=> '17024',
				'audio_details'	=> 'eng:421',
			},
		],
	},
	{
		'pid'	=> 602,
		'pids'	=> [
			{
				'video'	=> '601',
				'tsid'	=> '24576',
				'lcn'	=> '24',
				'name'	=> 'ITV4',
				'ca'	=> '0',
				'net'	=> 'ITV',
				'audio'	=> '602',
				'teletext'	=> '0',
				'subtitle'	=> '603',
				'type'	=> 'audio',
				'pnr'	=> '28032',
				'audio_details'	=> 'eng:602 eng:604',
			},
			{
				'video'	=> '204',
				'tsid'	=> '16384',
				'lcn'	=> '87',
				'name'	=> 'Community',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '411',
				'teletext'	=> '0',
				'subtitle'	=> '602',
				'type'	=> 'subtitle',
				'pnr'	=> '19968',
				'audio_details'	=> 'eng:411 eng:415',
			},
			{
				'video'	=> '600',
				'tsid'	=> '8199',
				'lcn'	=> '33',
				'name'	=> 'ITV2 +1',
				'ca'	=> '0',
				'net'	=> 'ITV',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '603',
				'type'	=> 'audio',
				'pnr'	=> '8362',
				'audio_details'	=> 'eng:601 eng:602',
			},
			{
				'video'	=> '600',
				'tsid'	=> '4107',
				'lcn'	=> '1',
				'name'	=> 'BBC ONE',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'audio',
				'pnr'	=> '4171',
				'audio_details'	=> 'eng:601 eng:602 fra:9999 deu:9900',
			},
		],
	},
	{
		'pid'	=> 6273,
		'pids'	=> [
			{
				'video'	=> '6273',
				'tsid'	=> '12290',
				'lcn'	=> '23',
				'name'	=> 'bid tv',
				'ca'	=> '0',
				'net'	=> 'Sit-Up Ltd',
				'audio'	=> '6274',
				'teletext'	=> '8888',
				'subtitle'	=> '0',
				'type'	=> 'video',
				'pnr'	=> '14272',
				'audio_details'	=> 'eng:6274 fra:9999',
			},
		],
	},
	{
		'pid'	=> 8888,
		'pids'	=> [
			{
				'video'	=> '6273',
				'tsid'	=> '12290',
				'lcn'	=> '23',
				'name'	=> 'bid tv',
				'ca'	=> '0',
				'net'	=> 'Sit-Up Ltd',
				'audio'	=> '6274',
				'teletext'	=> '8888',
				'subtitle'	=> '0',
				'type'	=> 'teletext',
				'pnr'	=> '14272',
				'audio_details'	=> 'eng:6274 fra:9999',
			},
		],
	},
	{
		'pid'	=> 9999,
		'pids'	=> [
			{
				'video'	=> '6273',
				'tsid'	=> '12290',
				'lcn'	=> '23',
				'name'	=> 'bid tv',
				'ca'	=> '0',
				'net'	=> 'Sit-Up Ltd',
				'audio'	=> '6274',
				'teletext'	=> '8888',
				'subtitle'	=> '0',
				'type'	=> 'audio',
				'pnr'	=> '14272',
				'audio_details'	=> 'eng:6274 fra:9999',
			},
			{
				'video'	=> '600',
				'tsid'	=> '4107',
				'lcn'	=> '1',
				'name'	=> 'BBC ONE',
				'ca'	=> '0',
				'net'	=> 'BBC',
				'audio'	=> '601',
				'teletext'	=> '0',
				'subtitle'	=> '605',
				'type'	=> 'audio',
				'pnr'	=> '4171',
				'audio_details'	=> 'eng:601 eng:602 fra:9999 deu:9900',
			},
		],
	},
);

plan tests => scalar(@tests) ;
	
	foreach my $test_href (@tests)
	{
		test_pid($tuning_href, $test_href->{'pid'}, $test_href->{'pids'}) ;
	}

	exit 0 ;

#------------------------------------------------------------------------------------------------
sub test_pid
{
	my ($tuning_href, $pid, $expected_aref) = @_ ;

	my @pid_info = Linux::DVB::DVBT::Config::pid_info($pid, $tuning_href) ;
	
	is_deeply(\@pid_info, $expected_aref, "PID $pid info") ;
}
	
	
__END__

