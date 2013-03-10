use TokyoCabinet;
use strict;
use warnings;

# create the object
my $adb = TokyoCabinet::ADB->new();

# open the database
if(!$adb->open("casket.tch")){
    printf STDERR ("open error\n");
}

# store records
if(!$adb->put("foo", "hop") ||
   !$adb->put("bar", "step") ||
   !$adb->put("baz", "jump")){
    printf STDERR ("put error\n");
}

# retrieve records
my $value = $adb->get("foo");
if(defined($value)){
    printf("%s\n", $value);
} else {
    printf STDERR ("get error\n");
}

# traverse records
$adb->iterinit();
while(defined(my $key = $adb->iternext())){
    my $value = $adb->get($key);
    if(defined($value)){
        printf("%s:%s\n", $key, $value);
    }
}

# close the database
if(!$adb->close()){
    printf STDERR ("close error\n");
}

# tying usage
my %hash;
if(!tie(%hash, "TokyoCabinet::ADB", "casket.tch")){
    printf STDERR ("tie error\n");
}
$hash{"quux"} = "touchdown";
printf("%s\n", $hash{"quux"});
while(my ($key, $value) = each(%hash)){
    printf("%s:%s\n", $key, $value);
}
untie(%hash);
