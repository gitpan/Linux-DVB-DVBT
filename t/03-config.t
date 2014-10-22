use Data::Dumper ;

use Test::More tests => 4;

## Check module loads ok
BEGIN { use_ok('Linux::DVB::DVBT') };


##### Object methods

## Create object
my $dvb = Linux::DVB::DVBT->new(
	'dvb' => 1,		# special case to allow for testing
	
	'adapter_num'	=> 1,
	'frontend_num'	=> 0,
	
	'frontend_name'	=> '/dev/dvb/adapter1/frontend0',
	'demux_name'	=> '/dev/dvb/adapter1/demux0',
	'dvr_name'	=> '/dev/dvb/adapter1/dvr0',
	
) ;
isa_ok($dvb, 'Linux::DVB::DVBT') ;

## Check config read
$expected_config_href = {
          'ts' => {
                    '8199' => {
                                'transmission' => '2',
                                'guard_interval' => '32',
                                'code_rate_high' => '23',
                                'name' => 'Oxford/Bexley',
                                'frequency' => '850000000',
                                'modulation' => '64',
                                'bandwidth' => '8',
                                'code_rate_low' => '12',
                                'hierarchy' => '0'
                              },
                    '4107' => {
                                'transmission' => '2',
                                'guard_interval' => '32',
                                'code_rate_high' => '34',
                                'name' => 'Oxford/Bexley',
                                'frequency' => '578000000',
                                'modulation' => '16',
                                'bandwidth' => '8',
                                'code_rate_low' => '34',
                                'hierarchy' => '0'
                              }
                  },
          'pr' => {
                    'CBBC Channel' => {
                                        'audio' => '621',
                                        'video' => '620',
                                        'tsid' => '4107',
                                        'name' => 'CBBC Channel',
                                        'type' => '1',
                                        'net' => 'BBC',
                                        'pnr' => '4671',
                                        'audio_details' => 'eng:621 eng:622'
                                      },
                    'Channel 4' => {
                                     'audio' => '561',
                                     'video' => '560',
                                     'tsid' => '8199',
                                     'name' => 'Channel 4',
                                     'type' => '1',
                                     'net' => 'Channel 4 TV',
                                     'pnr' => '8384',
                                     'audio_details' => 'eng:561 eng:562'
                                   },
                    'BBC TWO' => {
                                   'audio' => '611',
                                   'video' => '610',
                                   'tsid' => '4107',
                                   'name' => 'BBC TWO',
                                   'type' => '1',
                                   'net' => 'BBC',
                                   'pnr' => '4235',
                                   'audio_details' => 'eng:611 eng:612'
                                 },
                    'ITV1' => {
                                'audio' => '521',
                                'video' => '520',
                                'tsid' => '8199',
                                'name' => 'ITV1',
                                'type' => '1',
                                'net' => 'ITV',
                                'pnr' => '8263',
                                'audio_details' => 'eng:521 eng:522'
                              },
                    'ITV4' => {
                                'audio' => '601',
                                'video' => '600',
                                'tsid' => '8199',
                                'name' => 'ITV4',
                                'type' => '1',
                                'net' => 'ITV',
                                'pnr' => '8353',
                                'audio_details' => 'eng:601 eng:602'
                              },
                    'BBC NEWS' => {
                                    'audio' => '641',
                                    'video' => '640',
                                    'tsid' => '4107',
                                    'name' => 'BBC NEWS',
                                    'type' => '1',
                                    'net' => 'BBC',
                                    'pnr' => '4415',
                                    'audio_details' => 'eng:641'
                                  },
                    'E4' => {
                              'audio' => '571',
                              'video' => '570',
                              'tsid' => '8199',
                              'name' => 'E4',
                              'type' => '1',
                              'net' => 'Channel 4 TV',
                              'pnr' => '8448',
                              'audio_details' => 'eng:571 eng:572'
                            },
                    'More 4' => {
                                  'audio' => '591',
                                  'video' => '590',
                                  'tsid' => '8199',
                                  'name' => 'More 4',
                                  'type' => '1',
                                  'net' => 'Channel 4 TV',
                                  'pnr' => '8442',
                                  'audio_details' => 'eng:591 eng:592'
                                }
                  }
        };



$dvb->config_path('./t/config') ;
my $tuning_href = $dvb->get_tuning_info() ;
#print Dumper($tuning_href) ;
is_deeply($tuning_href, $expected_config_href) ;

## Check config write
if ( -d './t/config-out' )
{
	system("rm -rf ./t/config-out") ;
}
$dvb->config_path('./t/config-out') ;
$dvb->tuning(0) ;
#print Dumper($expected_config_href) ;
Linux::DVB::DVBT::Config::write($dvb->config_path, $expected_config_href) ;
$tuning_href = $dvb->get_tuning_info() ;
is_deeply($tuning_href, $expected_config_href) ;



