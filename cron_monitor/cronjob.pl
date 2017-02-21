#!/usr/local/bin/perl5
use Data::Dumper;
use Date::Calc qw(Mktime Decode_Month Day_of_Week Days_in_Month);
use Time::Local;
use POSIX;
use MIME::Lite;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time());
$year+=1900;
#my $mail_list='tjndata@freescale.com';
my $mail_list='zhaoxin.liu@nxp.com';
my $time_end=time()-24*3600;
my ($user,$host)=map { /(.*)/; $1 } @ARGV;
my $bin="/exec/apps/tools/cron/cronmonitor/";
my $cronlog='/tmp/cronlog';
my $crontab=$bin."/crontab/cronlist_$user";
#my $crontab="/probeeng/probe/DATA_TEAM/LiuZX/cronlist_bak"or die $!;
die "unknow host:$host "if $host !~ /zch01app04v.ap.freescale.net/;
die "unknow user:$user "if $user !~ /(probe|webadmin)/;
open(LOG,"<","$cronlog") || die $!;
my $unit={};
open(CRON,"<","$crontab") || die $!;
#############################handle crontab###########################
while (my $line=<CRON>) {
        next if $line=~ /^#.*/;
        next if $line eq '';
        $line=~ s/\n//g;
        $line=~ /(([\w\,\/\*\-]+\s+){5})(.*)/;
        my $frequency=$1;
	my $cronjob=$3;
	$cronjob=~s/\s$//g;
        if (defined $unit->{$user}->{"$cronjob"}->{'fre'}) {
                my $ref=$unit->{$user}->{"$cronjob"}->{'fre'};
                push @$ref,$frequency;
        } else {
                my @frequency;
                push @frequency,$frequency;
                $unit->{$user}->{"$cronjob"}->{'fre'}=\@frequency;
        }
}
close CRON;
##############################handle cronlog###########################
while (my $line=<LOG> ) {
	next unless $line=~/(.*)\scrond\[\d*\]:\s\((.*)\)\sCMD\s\((.*)\)/;
	my $tmp=$1;
	my @tmp=split(/\s+/,$tmp);
	my $account=$2;
	my $cronjob=$3;
	$cronjob=~s/\s$//g;
	next if ($account ne $user);
	next unless defined $unit->{$account}->{"$cronjob"};
	my $MM=Decode_Month("$tmp[0]",1);
	my $dd=$tmp[1];
	my @mm=split(/:/,$tmp[2]);
	my $time=Mktime("$year","$MM","$dd","$mm[0]","$mm[1]",$mm[2]);
	next if $time<=$time_end;
	#print "$year,$MM,$dd,$mm[0],$mm[1],$mm[2]";
	#$time=strftime('%F %T',localtime($time));
	#print "$time\n$line\n";
	if (defined $unit->{$account}->{"$cronjob"}->{'time'}) { 
		my $ref=$unit->{$account}->{"$cronjob"}->{'time'};	
		push @$ref,$time;
	} else {
		my @time;
		push @time,$time;
		$unit->{$account}->{"$cronjob"}->{'time'}=\@time;
	}
}
#print Dumper($unit);
close LOG;
##########################analysis cronjob##########################3
my $cronlist=$unit->{$user};
my $result;
foreach $job (keys %$cronlist) {
	my $fre=$cronlist->{$job}->{'fre'};
	my $list_time=$cronlist->{$job}->{'time'};
	my @cal_list;
	foreach my $fre_list (@$fre){
		my $tmp_cal_list=&Anaylze($fre_list,$list_time);
		push @cal_list,@$tmp_cal_list;
	}
	my @result=&diff(\@cal_list,$list_time);
	if ( @result !=0) {
		my $error_list=join(', ',@result);
		my $str="Cronjob: $job .\nshould excute time: $error_list\n\n";
		$result.=$str;
	}
}
#print "result:$result";
if ($result ne "") {
	&sendmail($mail_list,$result);
}
#####################End######################################################
sub Anaylze {
	my $frequence=shift;
	my $ref_time=shift;
	my @time=@$ref_time;
	@time=sort{$a<=>$b}@time;
	my @fre=split(/\s+/,$frequence);
	my @mm=&tranform($fre[0]);
	my @hh=&tranform($fre[1]);
	my @dd=&tranform($fre[2]);
	my @MM=&tranform($fre[3]);
	my @ww=&tranform($fre[4]);
	if ( $mm[1] ==3 || $hh[1] ==3 || $dd[1]==3 || $MM[1] ==3 || $ww[1] ==3){
		warn "Unknow format";
		return;
	}
	my $ref_cal_list;
############list mon time#########
	$ref_cal_list=&time_list(\@MM,'MM',$ref_time);
	#print Dumper($ref_cal_list);
##########list day time ##########
	$ref_cal_list=&time_list(\@dd,'dd',$ref_cal_list);	
	#print Dumper($ref_cal_list);
	#exit;
#########list hour time ############
        $ref_cal_list=&time_list(\@hh,'hh',$ref_cal_list); 
	#@$ref_cal_list=map(strftime('%F %T',localtime($_)),@$ref_cal_list);
	#print Dumper($ref_cal_list);
	#exit;
#######list min time ##############
        $ref_cal_list=&time_list(\@mm,'mm',$ref_cal_list); 
	#@$ref_cal_list=map(strftime('%F %T',localtime($_)),@$ref_cal_list);
	#print Dumper($ref_cal_list);
	my @fianl_list;
#######list week time ############
	if ($ww[1] ==0 ) {
		my $ref_ww=$ww[0];
		foreach my $ww_list (@$ref_ww) {
			foreach my $tmp_time (@$ref_cal_list) {
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($tmp_time);			
				if ($wday==$ww_list) {
					next if $tmp_time>time();
					next if $tmp_time<$time_end;
					push @fianl_list,$tmp_time;
				}
			}
		}
	} else {
		foreach my $tmp_time (@$ref_cal_list){
			next if $tmp_time>time();
			next if $tmp_time<$time_end;
		#	print strftime('%F %T',localtime($tmp_time))."\n";	
			push @fianl_list,$tmp_time;
		}
	}
=prod
	@fianl_list=sort(@fianl_list);
	my @fianl=map(strftime('%F %T',localtime($_)),@fianl_list);
	my @fianl1=map(strftime('%F %T',localtime($_)),@time);
	print Dumper(\@fianl);
        print Dumper(\@fianl1);
=cut
#########return calculate time list#################
	return \@fianl_list;
}
####################convert cron frequency to time list#########################
sub time_list {
	my ($ref_frequence,$type,$ref_cal_list)=@_;
	my @fre=@$ref_frequence;	
	my $ref=$fre[0];
	my @time_mask=@$ref;
	my @cal_list=@$ref_cal_list;
	my $time;
	my @result;
        if ( $fre[1] == 1) {
		my $time=$cal_list[0];
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time());
		$time=timelocal(0,0,0,$mday,$mon,$year) if $time eq '';
                while(1) {
			my $rate;
			if ($type eq "MM") {
				if ($mon==0) {
					$mon=11;
					$year-=1;
				} else {
					$mon-=1;
				}
				$rate=Days_in_Month($year,$mon+1)*3600*24;
			} elsif ($type  eq 'dd'){
				$rate=24*3600;
			} elsif ($type eq "hh"){
				$rate=3600;
			} elsif ($type eq "mm"){
				$rate=60;
			}
			#print "$type".strftime('%F %T',localtime($time))."\n";
			push @result,$time;
                        $time+=$time_mask[0]*$rate;
			my ($sec_,$min_,$hour_,$mday_,$mon_,$year_,$wday_,$yday_,$isdst_)=localtime($time);
                        if ($type eq "MM") {
				if ($year_==$year){
					last if $mon_>$mon;
				}
                        } elsif ($type  eq 'dd'){
				if ($year_==$year and $mon_==$mon){
					last if $mday_>$mday;
				}
                        } elsif ($type eq "hh"){
				if ($year_==$year and $mon_==$mon and $mday_==$mday){
					last if $hour_>$hour;
				}
                        } elsif ($type eq "mm"){
				if ($hour_==$hour and $mday_==$mday and $mon_==$mon and $year_==$year){
					last if $min_>$min;
				}
                        }

		#	print strftime('%F %T',localtime($time));
		#	print "\n";
                }
        } elsif ($fre[1] == 0) {
			for ( my $i=0;$i<@cal_list;$i++) {
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($cal_list[$i]);
                        	foreach my $tmp_fre (@time_mask){
					if ($type eq "MM") {
					#next if $tmp_fre==$mon;
                                		$time=timelocal($sec,$min,$hour,$mday,$tmp_fre,$year);
					} elsif ($type eq 'dd'){
					#next if $tmp_fre==$mday;
						$time=timelocal($sec,$min,$hour,$tmp_fre,$mon,$year);
					} elsif ($type eq "hh"){
					#next if $tmp_fre==$hour;
						$time=timelocal($sec,$min,$tmp_fre,$mday,$mon,$year);
					} elsif ($type eq "mm"){
					#next if $tmp_fre==$min;
						$time=timelocal($sec,$tmp_fre,$hour,$mday,$mon,$year);
					}
#                               		next if $time<$time_end;
#					next if $time>$cal_list[@cal_list-1];
                                	push @result,$time;
                        	}
			}
        }	
	return \@result;
}
############################convert cron frequency##################
sub tranform {
	my $fre=shift;
	my @plan_time;
	if ($fre!~/\*/) {
            @block=split(/\,/,$fre);
		foreach $block (@block) {
                	if ($block=~/(\d+)\-(\d+)/) {
				my $start=$1;
				my $end=$2;
				return 'error' if ($start>$end);
				for (my $i=$start;$i<=$end;$i++) {
					push @plan_time,$i;
				}
                	} elsif ($block=~/\d/) {
				push @plan_time,$block;
			}
		}
		return (\@plan_time,0);
        } elsif ($fre=~/\*\/?(\d*)/) {
		if ($1=='') {
			push @plan_time,1;
		} else {
			push @plan_time,$1;
		}
		return (\@plan_time,1);	
	} else {
		return ('Unknow format:$fre',3);
	}
}
####################analysis if cronjob run at time ########################333
sub diff {
	my ($array1,$array2) = @_;
	@$array1=map(strftime('%Y-%m-%d %H:%M',localtime($_)),@$array1);
	@$array2=map(strftime('%Y-%m-%d %H:%M',localtime($_)),@$array2);
        #print "$array1,$array2\n";
        my @array3;
        my %count = ();
        foreach my $element(@$array1,@$array2){
                $count{$element}++;
        }
        foreach my $element (keys %count){
        	if( $count{$element} != 2 ){
			push @array3,$element
		}
        }
        return sort @array3;
}
sub sendmail{
	my $mail_list=shift;
	my $text=shift;
        $msg = MIME::Lite->new(
                From => 'cron monitor system',
                To => "$mail_list",
                Type => 'multipart/mixed',
                Subject => "Host:$host Account:$user"
                );
                $msg->attach(
                Type => 'TEXT',
                Data => "Hello:\n\n".
                        "This is conjob monitor system\n\n".
                        "Below cronjob not excuted on time\n\n".
			"$text\n\n".
                        "This is an automatic email sent by the  system, please do not reply."
        );
        # Attachment
        $msg->send or die $!;
}

