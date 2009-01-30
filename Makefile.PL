#use 5.008008;
use 5.006;
use ExtUtils::MakeMaker qw(prompt WriteMakefile);
use Config;
use strict;

my @programs_to_install = qw(dvbt-epg dvbt-ffrec dvbt-record dvbt-scan);
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
    NAME              => 'Linux::DVB::DVBT',
    VERSION_FROM      => 'lib/Linux/DVB/DVBT.pm', # finds $VERSION
    PREREQ_PM         => {
		'File::Basename'	=> 0,
		'File::Path' 		=> 0,
		'File::Spec' 		=> 0,
		'POSIX'			=> 0,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Linux/DVB/DVBT.pm', # retrieve abstract from module
       AUTHOR         => 'Steve Price <cpan@sdprice.plus.com>') : ()),
    LIBS              => [''], # e.g., '-lm'
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
$(MYEXTLIB): dvb_lib/Makefile 
	cd dvb_lib && $(MAKE) $(PASSTHRU)
';
}

