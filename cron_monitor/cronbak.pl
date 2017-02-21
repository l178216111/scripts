#!/usr/local/bin/perl5
use Time::Local;
use POSIX;
my $time=time();
my $usr=$ENV{'USER'};
my $bin='/exec/apps/tools/cron/cronmonitor';
&checkdaemon;
&bakcrontab;
sub checkdaemon{
	my $process=`ps -edf | grep cronmonitor_daemon.pl | grep -v grep`;
	if ($process eq "") {
        	$process=system("$bin/cronmonitor_daemon.pl &");
        	warn "cronmonitor_deamon restart on ".strftime('%F %T',localtime($time));
	}
}
sub bakcrontab{
	my $cmd=`crontab -l`;
	my $cronlist_current=$bin."/crontab/cronlist_$usr$time";
	my $cronlist_bak=$bin."/crontab/cronlist_$usr";
	open(CRON,'>',$cronlist_current) || die $!;     
	print CRON "$cmd";
	close CRON;
	if (-e $cronlist_bak) {
		my $diff=`diff $cronlist_current $cronlist_bak`;
		if ($diff eq '') {
        		unlink $cronlist_current || die $!;
		} else {
               		rename $cronlist_bak,$cronlist_bak."oldversion" || die $!;
        		rename $cronlist_current,$cronlist_bak || die $!;
		}
	} else {
		rename $cronlist_current,$cronlist_bak || die $!;
	}
}
