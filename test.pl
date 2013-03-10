#! /usr/bin/perl

use lib qw(./blib/lib ./blib/arch);
use strict;
use warnings;
use Test::More qw(no_plan);
use TokyoCabinet;
$TokyoCabinet::DEBUG = 1;

my @commands = (
                "tchtest.pl write casket 10000",
                "tchtest.pl read casket",
                "tchtest.pl remove casket",
                "tchtest.pl misc casket 1000",
                "tchtest.pl write -tl -as -td casket 10000 10000 1 1",
                "tchtest.pl read -nl casket",
                "tchtest.pl remove -nb casket",
                "tchtest.pl misc -tl -tb casket 1000",
                "tcbtest.pl write casket 10000",
                "tcbtest.pl read casket",
                "tcbtest.pl remove casket",
                "tcbtest.pl misc casket 1000",
                "tcbtest.pl write -tl casket 10000 10 10 100 1 1",
                "tcbtest.pl read -nl casket",
                "tcbtest.pl remove -nb casket",
                "tcbtest.pl misc -tl -tb casket 1000",
                "tcftest.pl write casket 10000",
                "tcftest.pl read casket",
                "tcftest.pl remove casket",
                "tcftest.pl misc casket 1000",
                "tcttest.pl write -ip -is -in casket 1000",
                "tcttest.pl read casket",
                "tcttest.pl remove casket",
                "tcttest.pl misc casket 500",
                "tcttest.pl write -tl -is -td casket 1000 1000 1 1",
                "tcttest.pl read -nl casket",
                "tcttest.pl remove -nb casket",
                "tcttest.pl misc -tl -tb casket 500",
                "tcatest.pl write 'casket.tch#mode=wct' 10000",
                "tcatest.pl read 'casket.tch#mode=r'",
                "tcatest.pl remove 'casket.tch#mode=w'",
                "tcatest.pl misc 'casket.tch#mode=wct' 1000",
                );

foreach my $command (@commands){
    my $rv = system("$^X $command >/dev/null");
    ok($rv == 0, $command);
}

system("rm -rf casket*");
