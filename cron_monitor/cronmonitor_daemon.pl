#!/usr/local/bin/perl5
my $scope=3600;
my $cronlog="/tmp/cronlog";
my $host=`hostname`;
my $cmd="/exec/apps/tools/cron/cronmonitor/cronjob.pl";
while(1){
	foreach my $user ('probe','webadmin'){
		my $genlog=`sudo /bin/cat /var/log/cron > $cronlog`;
		system("$cmd $user $host");
	}
	sleep $scope;
}
