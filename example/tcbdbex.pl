use TokyoCabinet;
use strict;
use warnings;

# create the object
my $bdb = TokyoCabinet::BDB->new();

# open the database
if(!$bdb->open("casket.tcb", $bdb->OWRITER | $bdb->OCREAT)){
    my $ecode = $bdb->ecode();
    printf STDERR ("open error: %s\n", $bdb->errmsg($ecode));
}

# store records
if(!$bdb->put("foo", "hop") ||
   !$bdb->put("bar", "step") ||
   !$bdb->put("baz", "jump")){
    my $ecode = $bdb->ecode();
    printf STDERR ("put error: %s\n", $bdb->errmsg($ecode));
}

# retrieve records
my $value = $bdb->get("foo");
if(defined($value)){
    printf("%s\n", $value);
} else {
    my $ecode = $bdb->ecode();
    printf STDERR ("get error: %s\n", $bdb->errmsg($ecode));
}

# traverse records
my $cur = TokyoCabinet::BDBCUR->new($bdb);
$cur->first();
while(defined(my $key = $cur->key())){
    my $value = $cur->val();
    if(defined($value)){
        printf("%s:%s\n", $key, $value);
    }
    $cur->next();
}

# close the database
if(!$bdb->close()){
    my $ecode = $bdb->ecode();
    printf STDERR ("close error: %s\n", $bdb->errmsg($ecode));
}

# tying usage
my %hash;
if(!tie(%hash, "TokyoCabinet::BDB", "casket.tcb", TokyoCabinet::BDB::OWRITER)){
    printf STDERR ("tie error\n");
}
$hash{"quux"} = "touchdown";
printf("%s\n", $hash{"quux"});
while(my ($key, $value) = each(%hash)){
    printf("%s:%s\n", $key, $value);
}
untie(%hash);
