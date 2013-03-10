use TokyoCabinet;
use strict;
use warnings;

# create the object
my $tdb = TokyoCabinet::TDB->new();

# open the database
if(!$tdb->open("casket.tct", $tdb->OWRITER | $tdb->OCREAT)){
    my $ecode = $tdb->ecode();
    printf STDERR ("open error: %s\n", $tdb->errmsg($ecode));
}

# store a record
my $pkey = $tdb->genuid();
my $cols = { "name" => "mikio", "age" => "30", "lang" => "ja,en,c" };
if(!$tdb->put($pkey, $cols)){
    my $ecode = $tdb->ecode();
    printf STDERR ("put error: %s\n", $tdb->errmsg($ecode));
}

# store another record
$cols = { "name" => "falcon", "age" => "31", "lang" => "ja", "skill" => "cook,blog" };
if(!$tdb->put("x12345", $cols)){
    my $ecode = $tdb->ecode();
    printf STDERR ("put error: %s\n", $tdb->errmsg($ecode));
}

# search for records
my $qry = TokyoCabinet::TDBQRY->new($tdb);
$qry->addcond("age", $qry->QCNUMGE, "20");
$qry->addcond("lang", $qry->QCSTROR, "ja,en");
$qry->setorder("name", $qry->QOSTRASC);
$qry->setlimit(10);
my $res = $qry->search();
foreach my $rkey (@$res){
    my $rcols = $tdb->get($rkey);
    printf("name:%s\n", $rcols->{name});
}

# close the database
if(!$tdb->close()){
    my $ecode = $tdb->ecode();
    printf STDERR ("close error: %s\n", $tdb->errmsg($ecode));
}

# tying usage
my %hash;
if(!tie(%hash, "TokyoCabinet::TDB", "casket.tct", TokyoCabinet::TDB::OWRITER)){
    printf STDERR ("tie error\n");
}
$hash{"joker"} = { "name" => "ozma", "lang" => "en", "skill" => "song,dance" };
printf("%s\n", $hash{joker}->{name});
while(my ($key, $value) = each(%hash)){
    printf("%s:%s\n", $key, $value->{name});
}
untie(%hash);
