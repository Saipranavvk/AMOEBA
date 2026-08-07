package FindBin;

use strict;
use warnings;
use Cwd qw(abs_path getcwd);

our ($Bin, $Dir, $Script, $RealBin, $RealScript);

BEGIN {
    my $path = $0;
    $path = "./$path" if $path !~ m{/};

    ($Bin, $Script) = $path =~ m{^(.*)/(.*)$};
    $Bin = "." if !defined($Bin) || $Bin eq "";
    $Dir = $Bin;

    my $cwd = getcwd();
    my $abs_bin = $Bin =~ m{^/} ? $Bin : "$cwd/$Bin";
    $RealBin = abs_path($abs_bin) || $abs_bin;
    $RealScript = $Script;
}

sub import {
    my ($pkg, @symbols) = @_;
    my $caller = caller;

    no strict 'refs';
    for my $symbol (@symbols) {
        next if $symbol !~ /^\$(.+)$/;
        *{"${caller}::$1"} = \${"${pkg}::$1"};
    }
}

1;
