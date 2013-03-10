#=================================================================================================
# Script for MakeMaker
#=================================================================================================


use ExtUtils::MakeMaker;
use strict;
use warnings;


# check configuration
my $home = $ENV{"HOME"};
$ENV{"PATH"} = $ENV{"PATH"} . ":/usr/local/bin:$home/bin:.:..:../..";
my $inc = `tcucodec conf -i 2>/dev/null`;
chomp($inc);
if(length($inc) < 2){
    $inc = "-I/usr/local/include -I$home/include -I.";
}
my $libs = `tcucodec conf -l 2>/dev/null`;
chomp($libs);
if(length($libs) < 2){
    $libs = "-L/usr/local/lib -L$home/lib -L. -ltokyocabinet -lz -lbz2 -lpthread -lm -lc";
}


# Create Makefile
WriteMakefile(
    'NAME'              => 'TokyoCabinet',
    'VERSION_FROM'      => 'TokyoCabinet.pm',
    'INC'               => $inc,
    'LIBS'              => $libs,
    'clean'             => { FILES => "casket* *~ hoge moge" },
);



# END OF FILE
