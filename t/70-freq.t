#!perl

use strict;
use warnings;
use Test::More ;

use Linux::DVB::DVBT ;
use Linux::DVB::DVBT::Freq ;

my @args = (

	{'iso3166'=>'GB',	'results'=>[
							177500000,
							184500000,
							191500000,
							198500000,
							205500000,
							212500000,
							219500000,
							226500000,
							474000000,
							482000000,
							490000000,
							498000000,
							506000000,
							514000000,
							522000000,
							530000000,
							538000000,
							546000000,
							554000000,
							562000000,
							570000000,
							578000000,
							586000000,
							594000000,
							602000000,
							610000000,
							618000000,
							626000000,
							634000000,
							642000000,
							650000000,
							658000000,
							666000000,
							674000000,
							682000000,
							690000000,
							698000000,
							706000000,
							714000000,
							722000000,
							730000000,
							738000000,
							746000000,
							754000000,
							762000000,
							770000000,
							778000000,
							786000000,
							794000000,
							802000000,
							810000000,
							818000000,
							826000000,
							834000000,
							842000000,
							850000000,
							858000000,
		]},

) ;


	my $checks_per_test = 1 ;
	plan tests => scalar(@args) * $checks_per_test ;
	

	my @freqs ;
	my @freqs2 ;
	my $test_num=1 ;
	foreach my $args_href (@args)
	{
		@freqs = Linux::DVB::DVBT::Freq::freq_list($args_href->{'iso3166'}) ;
		@freqs2 = Linux::DVB::DVBT::Freq::chan_freq_list($args_href->{'iso3166'}) ;
		is_deeply(\@freqs, $args_href->{'results'}) ;
		
#Linux::DVB::DVBT::prt_data("Freqs for $args_href->{'iso3166'} = ", \@freqs) ;	

		print "Frequencies for $args_href->{'iso3166'}\n" ;
		foreach my $href (@freqs2)
		{
			printf "%2d : $href->{'freq'}\n", $href->{'chan'} ;
		}	
	}
	exit 0 ;

	
	
__END__

