#!/usr/local/bin/perl5
#####################################################
#Author:zhaoxin.liu
#Usage:Monitor substrateid 
####################################################
use MIME::Lite;
use Data::Dumper;
use strict;
use warnings;
my $time=time();
my $filecn=0;
my $dircn=0;
my ($maillist,$cclist);
#$maillist='zhaoxin.liu@nxp.com';
$maillist='tjndata@nxp.com';
$cclist='zhaoxin.liu@nxp.com';
my $result="";
sub lsr_s {
    my $cwd = shift;
    my @dirs = ($cwd.'/');
    my ($dir, $file);
    while ($dir = pop(@dirs)) {
        local *DH;
        if (!opendir(DH, $dir)) {
            warn "Cannot opendir $dir: $!\n";
            next;
        }
        foreach (readdir(DH)) {
            if ($_ eq '.' || $_ eq '..') {
                next;
            }
            $file = $dir.$_;         
            if (!-l $file && -d _) {
                $file .= '/';
                push(@dirs, $file);
            }
            &process($file,$dir);
        }
        closedir(DH);
    }
}
sub process{
	my $file = shift;
	if (!(-d $file)){	
			$filecn+=1;
#                       $file=/floor/data/results_map/WB01M72Y/TM56772.1C/r_1-1
			my @tmp_file=split(/\//,$file);
			return if ( @tmp_file < 7 );
			my ($part,$lot,$wafer)=("","","");
			$part=$tmp_file[4];
			$lot=$tmp_file[5] if $tmp_file[5]=~ /\w{1,2}\d{5}\.\d\w/;
			return if ($lot=~/^(KK|GG|C)/);
			$wafer=$1 if $tmp_file[6]=~ /^r_1-(\d+)$/;		
			return if ( $wafer eq "");
			my $subtime=$time-(stat($file))[9]; 
# 1 min<update time < 1hour 2mins
			if ($subtime <=60*60+120 && $subtime >= 60){
#			print "($part,$lot,$wafer)\n";
				open(INF,'<',"$file") or warn $!;
				my $substrateid=0; 
				while (<INF>){
					if ($_=~/SUBSTRATEID:|SESSION_RESULTS:.*INTERRUPTED\s*$/){
						$substrateid=1;
						last;
					}
					last if ($_=~/^SmWafer$/);
				}
				close INF;
				if ($substrateid == 0){
					$result.="$file\n";		
					my $cmd=&man_substrateid($part,$lot,$wafer);
					$result.="$cmd\n";
				}
		}
	}else{
		$dircn+=1;
	}
}
sub send_mail{
	my ($text,$summarize)=@_;
	my $msg;
        $msg = MIME::Lite->new(
                From => 'INF scan system',
                To => "$maillist",
                Cc => "$cclist",
                Type => 'multipart/mixed',
                Subject => "INF value scan"
                );
                $msg->attach(
                Type => 'TEXT',
                Data => "Hello,below INF can't find Substrateid\n\n".
			"$text".
			"Summarize:\n\n".
			$summarize.
                        "\n\nThis is an automatic email sent by the INF scan system, please do not reply."
        );
	$msg->send or return $@;
}
sub man_substrateid{
	my ($part,$lot,$wafer)=@_;
	my $cmd_addsubstateid="/exec/apps/bin/ewmbin/man_substrateid.pl";
	my $cmd=`$cmd_addsubstateid $part $lot $wafer` or warn $@;
	return $cmd;
}
&lsr_s('/floor/data/results_map');
my $runtime=time()-$time;
my $summarize="Runtime:$runtime sec File count:$filecn Dir count:$dircn\n";
&send_mail($result,$summarize) if ($result ne "");
print $summarize;
