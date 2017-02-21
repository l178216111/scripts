#!/usr/local/bin/perl5
use lib "/exec/apps/bin/lib/perl5";
use CONFAnalysis;
die "Usage:./config_load_sim.pl blcok configpath" if (@ARGV < 2);
my ($block,$config)=map { /(.*)/;$! } @ARGV;
my $sth=CONFAnalysis->new();
$sth->LoadCONF($config) || die $!;
my $match=$sth->mask_block($block);
print "Match blcok:$match";
