#!perl

use strict;
use warnings;
use Test::More ;

use Linux::DVB::DVBT::Utils ;

my @tests = (
	{
		'raw'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. (1/18)',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head.',
		'title'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. (1/18)',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
	},
	{
		'raw'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. 1 / 18',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its',
		'title'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. 1 / 18',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
	},
	{
		'raw'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. Epi 1 of 18',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head.',
		'title'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. Epi 1 of 18',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
	},
	{
		'raw'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. (Part 16 of 26)',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. (Part 16 of 26)',
		'subtitle'	=> '',
		'episode'	=> 16,
		'episodes'	=> 26,
	},
	{
		'raw'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. Part 16 of 26',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. Part 16 of 26',
		'subtitle'	=> '',
		'episode'	=> 16,
		'episodes'	=> 26,
	},
	{
		'raw'	=> 'The Gorilla Experiment: Penny feels left out when Bernadette shows an interest in science and asks Sheldon to educate her.',
		'text'	=> 'The Gorilla Experiment: Penny feels left out when Bernadette shows an interest in science and asks Sheldon to educate her.',
		'title'	=> 'The Gorilla Experiment: Penny feels left out when Bernadette shows an interest in science and asks Sheldon to educate her.',
		'subtitle'	=> 'The Gorilla Experiment',
		'episode'	=> 0,
		'episodes'	=> 0,
	},
	{
		'raw'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'text'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'title'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'subtitle'	=> 'Blood Wedding (Part 1)',
		'episode'	=> 0,
		'episodes'	=> 0,
	},
);

my @checks = (
	['title',		'Title unchanged'],
	['text',		'Text check'],
	['subtitle',	'Subtitle check'],
	['episode',		'Episode count check'],
	['episodes',	'Number of episodes check'],
) ;


plan tests => scalar(@tests) * scalar(@checks) ;

	foreach my $test_href (@tests)
	{
		my $text = $test_href->{'raw'} ;
		my %results = (
			'text'		=> $text,
			'title'		=> $text,
			'subtitle'	=> '',
			'episode'	=> 0,
			'episodes'	=> 0,
		) ;
		
		Linux::DVB::DVBT::Utils::fix_episodes(\$results{title}, \$results{text}, \$results{episode}, \$results{episodes}) ;
		$results{subtitle} = Linux::DVB::DVBT::Utils::subtitle($results{text}) ;
		
		foreach my $aref (@checks)
		{
			my ($key, $msg) = @$aref ;
			is($results{$key}, $test_href->{$key}, $msg) ;
		}
		
	}
	
