use TokyoCabinet;
use strict;
use warnings;

# create the object
my $fdb = TokyoCabinet::FDB->new();

# open the database
if(!$fdb->open("casket.tcf", $fdb->OWRITER | $fdb->OCREAT)){
    my $ecode = $fdb->ecode();
    printf STDERR ("open error: %s\n", $fdb->errmsg($ecode));
}

# store records
if(!$fdb->put(1, "one") ||
   !$fdb->put(12, "twelve") ||
   !$fdb->put(144, "one forty four")){
    my $ecode = $fdb->ecode();
    printf STDERR ("put error: %s\n", $fdb->errmsg($ecode));
}

# retrieve records
my $value = $fdb->get(1);
if(defined($value)){
    printf("%s\n", $value);
} else {
    my $ecode = $fdb->ecode();
    printf STDERR ("get error: %s\n", $fdb->errmsg($ecode));
}

# traverse records
$fdb->iterinit();
while(defined(my $key = $fdb->iternext())){
    my $value = $fdb->get($key);
    if(defined($value)){
        printf("%s:%s\n", $key, $value);
    }
}

# close the database
if(!$fdb->close()){
    my $ecode = $fdb->ecode();
    printf STDERR ("close error: %s\n", $fdb->errmsg($ecode));
}

# tying usage
my %hash;
if(!tie(%hash, "TokyoCabinet::FDB", "casket.tcf", TokyoCabinet::FDB::OWRITER)){
    printf STDERR ("tie error\n");
}
$hash{1728} = "seventeen twenty eight";
printf("%s\n", $hash{1728});
while(my ($key, $value) = each(%hash)){
    printf("%s:%s\n", $key, $value);
}
untie(%hash);
