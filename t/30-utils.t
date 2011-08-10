#!perl

use strict;
use warnings;
use Test::More ;

use Linux::DVB::DVBT::Utils ;

my @tests = (
	{
		'raw-title'	=> 'Numb3rs',
		'raw-text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. (1/18)',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head.',
		'title'	=> 'Numb3rs',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Numb3rs',
		'raw-text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. 1 / 18',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its',
		'title'	=> 'Numb3rs',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Numb3rs',
		'raw-text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head. Epi 1 of 18',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head.',
		'title'	=> 'Numb3rs',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Vets',
		'raw-text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. (Part 16 of 26)',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'Vets',
		'subtitle'	=> 'An obese parrot causes complications for vet Matt Brash',
		'episode'	=> 16,
		'episodes'	=> 26,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Vets',
		'raw-text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. Part 16 of 26',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'Vets',
		'subtitle'	=> 'An obese parrot causes complications for vet Matt Brash',
		'episode'	=> 16,
		'episodes'	=> 26,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Vets',
		'raw-text'	=> 'New  . An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. Part 16 of 26',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'Vets',
		'subtitle'	=> 'An obese parrot causes complications for vet Matt Brash',
		'episode'	=> 16,
		'episodes'	=> 26,
		'new_program' => 1,
	},
	{
		'raw-title'	=> 'Vets',
		'raw-text'	=> 'ALL      neW episodes  !! An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging. Part 16 of 26',
		'text'	=> 'An obese parrot causes complications for vet Matt Brash. He must also help a cat deliver kittens by emergency caesarean and a swan recovers from a brutal mugging.',
		'title'	=> 'Vets',
		'subtitle'	=> 'An obese parrot causes complications for vet Matt Brash',
		'episode'	=> 16,
		'episodes'	=> 26,
		'new_program' => 1,
	},
	{
		'raw-title'	=> 'Vets',
		'raw-text'	=> 'The Gorilla Experiment: Penny feels left out when Bernadette shows an interest in science and asks Sheldon to educate her.',
		'text'	=> 'The Gorilla Experiment: Penny feels left out when Bernadette shows an interest in science and asks Sheldon to educate her.',
		'title'	=> 'Vets',
		'subtitle'	=> 'The Gorilla Experiment',
		'episode'	=> 0,
		'episodes'	=> 0,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Midsomer',
		'raw-text'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'text'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'title'	=> 'Midsomer',
		'subtitle'	=> 'Blood Wedding (Part 1)',
		'episode'	=> 0,
		'episodes'	=> 0,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Midsomer',
		'raw-text'	=> 'New. Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'text'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'title'	=> 'Midsomer',
		'subtitle'	=> 'Blood Wedding (Part 1)',
		'episode'	=> 0,
		'episodes'	=> 0,
		'new_program' => 1,
	},
	{
		'raw-title'	=> 'Midsomer',
		'raw-text'	=> 'Brand new series! Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'text'	=> 'Blood Wedding (Part 1): Two weddings are due to take place - Cully\'s to Simon, and that of local baronet Ned Fitzroy. Then the maid of honour at Fitzroy\'s nuptials is found dead.',
		'title'	=> 'Midsomer',
		'subtitle'	=> 'Blood Wedding (Part 1)',
		'episode'	=> 0,
		'episodes'	=> 0,
		'new_program' => 1,
	},
	{
		'raw-title'	=> 'Numb3rs',
		'raw-text'	=> '1/18. Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head',
		'text'	=> 'Trust Metric: Colby escapes while being interrogated and Don and the team must find him. They receive fresh information about Colby that turns the investigation on its head',
		'title'	=> 'Numb3rs',
		'subtitle'	=> 'Trust Metric',
		'episode'	=> 1,
		'episodes'	=> 18,
		'new_program' => 0,
	},
	{
		'raw-title'	=> 'Julian Fellowes Investigates...',
		'raw-text'	=> '...a Most Mysterious Murder. The Case of xxxx. Epi 10 of 22',
		'text'	=> 'The Case of xxxx.',
		'title'	=> 'Julian Fellowes Investigates a Most Mysterious Murder',
		'subtitle'	=> 'The Case of xxxx',
		'episode'	=> 10,
		'episodes'	=> 22,
		'new_program' => 0,
	},
);

my @checks = (
	['title',		'Title unchanged'],
	['text',		'Text check'],
	['subtitle',	'Subtitle check'],
	['episode',		'Episode count check'],
	['episodes',	'Number of episodes check'],
	['new_program',	'"New program" flag check'],
) ;


plan tests => scalar(@tests) * scalar(@checks) ;

	foreach my $test_href (@tests)
	{
		my %results = (
			'text'		=> $test_href->{'raw-text'},
			'title'		=> $test_href->{'raw-title'},
			'subtitle'	=> '',
			'episode'	=> 0,
			'episodes'	=> 0,
			'new_program' => 0,
		) ;
		
		my %flags ;
		Linux::DVB::DVBT::Utils::fix_title(\$results{title}, \$results{text}) ;
		Linux::DVB::DVBT::Utils::fix_episodes(\$results{title}, \$results{text}, \$results{episode}, \$results{episodes}) ;
		Linux::DVB::DVBT::Utils::fix_audio(\$results{title}, \$results{text}, \%flags) ;
		
		Linux::DVB::DVBT::Utils::fix_synopsis(\$results{title}, \$results{text}, \$results{new_program}) ;

		$results{subtitle} = Linux::DVB::DVBT::Utils::subtitle($results{text}) ;
		
		foreach my $aref (@checks)
		{
			my ($key, $msg) = @$aref ;
			$msg .= " - $test_href->{'raw-title'}" ;
			is($results{$key}, $test_href->{$key}, $msg) ;
		}
		
	}
	
__END__

