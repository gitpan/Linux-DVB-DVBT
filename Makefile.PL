#use 5.008008;
use 5.006;
use ExtUtils::MakeMaker qw(prompt WriteMakefile);
use Config;
use strict;

my $name = 'Linux-DVB-DVBT' ;

my $mod = $name ;
$mod =~ s%\-%::%g ;

my $modpath = $name ;
$modpath =~ s%\-%/%g ;

# See if newer version is available
check_new_version() ;


my @programs_to_install = qw(dvbt-epg dvbt-ffrec dvbt-record dvbt-scan dvbt-devices dvbt-chans);
my $install_bin = 1;

if ( 
	grep $_ eq '-n', @ARGV
	or grep /^LIB=/, @ARGV and not grep /^INSTALLSCRIPT=/, @ARGV 
) 
{
	@ARGV = grep $_ ne '-n', @ARGV;
	warn "Skipping installation of scripts...\n";
	@programs_to_install = ();
} 
else 
{
	warn <<EOW;

This program comes with several scripts which I would try to install in
directory $Config{installscript}.

To skip, rerun with option -n given to Makefile.PL.

EOW
}


# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => $mod,
    VERSION_FROM      => "lib/$modpath.pm", # finds $VERSION
    PREREQ_PM         => {
		'File::Basename'	=> 0,
		'File::Path' 		=> 0,
		'File::Spec' 		=> 0,
		'POSIX'			=> 0,
		'Test::Pod::Coverage'	=> 1.08,
		'Pod::Coverage' => 0.18,
		'Test::Pod' => 1.22,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => "lib/$modpath.pm", # retrieve abstract from module
       AUTHOR         => 'Steve Price <cpan@sdprice.plus.com>') : ()),
    LIBS              => ['-lrt'], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I./dvb_lib -I./libng', # e.g., '-I. -I/usr/include/other'
    EXE_FILES         => [ map "script/$_", @programs_to_install ],
 
 
    ##CCFLAGS			  => '-g -O0',
    OPTIMIZE	  => '-g',
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too

    MYEXTLIB          => 'dvb_lib/libdvb_lib$(LIB_EXT)', 

);

## ADDED SDP
sub MY::postamble {
'
# If make is called with TESTDEF defined then it passes this definition down to the library build to allow
# special test builds
MAKE_TEST_DEF=
ifdef TESTDEF
	MAKE_TEST_DEF="TESTDEF=$(TESTDEF)"
endif

## make libs
$(MYEXTLIB): dvb_lib/Makefile 
	cd dvb_lib && $(MAKE) $(MAKE_TEST_DEF) CCFLAGS="$(CCFLAGS)" CCCDLFLAGS="$(CCCDLFLAGS)"

## Clean up
clean:: dvb_lib_clean                                                                                                   
                                                                                                                        
dvb_lib_clean: FORCE                                                                                                    
	cd dvb_lib && $(MAKE) clean                                                                                     

## Optional doxygen documentation 
doxygen: FORCE
	cd doxygen && doxygen
';
}


sub check_new_version
{
	my $version = ExtUtils::MM_Unix->parse_version("lib/$modpath.pm");

	print "Installing Version: $version\n" ;
	
	## Check for newer version
	eval {
		require LWP::UserAgent;
	} ;
	if (!$@)
	{
		print "Checking for later version...\n" ;
		
		## specify user name so that I can filter out my builds
		my $user = $ENV{USER} || $ENV{USERNAME} || 'nobody' ;
		
		## check for OS-specific versions
		my $os = $^O ;
		my $url = "http://quartz.homelinux.com/CPAN/index.php?ver=$version&mod=$name&user=$user&os=$os" ;
		 
		my $ua = LWP::UserAgent->new;
		$ua->agent("CPAN-$name/$version") ;
		$ua->timeout(10);
		$ua->env_proxy;
		 
		my $response = $ua->get($url);
		if ($response->is_success) 
		{
			my $content = $response->content ;
			if ($content =~ m/Current version : ([\d\.]+)/m)
			{
				print "Latest CPAN version is $1\n" ;
			}
			if ($content =~ m/Newer version/m)
			{
				print "** NOTE: A newer version than this is available. Please downloaded latest version **\n" ;
			}
			else
			{
				print "Got latest version\n" ;
			}
		}
		else
		{
			print "Unable to connect, assuming latest\n" ;
			#print $response->status_line;
		}
	}
	
}
