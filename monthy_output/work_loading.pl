#!/usr/local/bin/perl5
use lib '/exec/apps/bin/lib/perl5';
use lib '/probeeng/webadmin/cgi-bin/monthly_output';
use POSIX;
use Time::Local;
use MIME::Lite;
use Data::Dumper;
use Spreadsheet::WriteExcel;
use Spreadsheet::ParseExcel;
require dbconnect;
use shift_block;
BEGIN{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time());
	$current_mon=$mon+1;
	$current_year=$year+1900;
	%tester_alis=(
		'sat34'=>'b3t4701',
	);
	$mon=12 if ($mon eq 0);
	if (defined @ARGV){
		my($_input_mon,$_last_year)=map { /(.*)/;$1 } @ARGV;
		$current_year+=-$_last_year;
		$_mon=$_input_mon-$mon-(12*$_last_year);
		$_mon+=-1;
		$last_mon=$ARGV[0];
	}else{
		$_mon=-1;
 		$last_mon=$mon;
	}
}
#my $mail_list='xiangyun.qin@nxp.com,zhaoxin.liu@nxp.com,zhaowei.liu@nxp.com,J.li@nxp.com,yun.zhang@nxp.com,yu.kang@nxp.com';
my $mail_list='zhaoxin.liu@nxp.com,xiangyun.qin@nxp.com';
#my $mail_list='zhaoxin.liu@nxp.com';
my $xls_file="shift_output_report $current_year-$last_mon.xls";
my $report_pathdir='/probeeng/webadmin/cgi-bin/monthly_output/report';
my @FOI_promis_log;
my @FOI_genesis_log;
###avoid the max column of excel##
my @Tester_log_1;
my @Tester_log_2;
my $unit={};
$unit=&tester_output($unit);
$unit=&FOI_output($unit);
#print Dumper($unit);
my $error=&genexcel($unit);
if ($error==1){ 
        $error=&sendmail;
        unless ($error==1){
                warn $error;
        }
}else{  
warn $error;
}       
######################
sub tester_output{
	my $unit=shift;
	my $unique={};
	my $dbh=DBI->connect(&getconn('tjn','jbstar')) or die $@;
	my $sql="select  TesterID, (TestEnd-to_date('1970-1-1 08:00:00','yyyy-mm-dd hh24:mi:ss'))*24*60*60,passid,sessionnumber,passnum,device,lot,slot from (
	(select KeyNumber, TestEnd, TesterID,passid,sessionnumber,passnum from InfLayerMap where
 	((passid='1' and sessionnumber='1' and passnum='1') 
	or (passid='2' and sessionnumber='2' and passnum='1') 
	or (passid='2' and sessionnumber='2' and passnum='3')
	or (passid='1' and sessionnumber='1' and passnum='3') 
	or (passid='3' and sessionnumber='3' and passnum='1') 
	or (passid='3' and sessionnumber='3' and passnum='3')
	or (passid='4' and sessionnumber='4' and passnum='1')
	or (passid='4' and sessionnumber='4' and passnum='3')
	or (passid='4' and sessionnumber='4' and passnum='3')
	or (passid='5' and sessionnumber='5' and passnum='1')
	or (passid='5' and sessionnumber='5' and passnum='3'))
	and testend between (trunc(add_months(sysdate,$_mon),'mm')+8/24) and (trunc(add_months(sysdate,$_mon+1),'mm')+8/24)
	union all
	select KeyNumber, TestEnd, TesterID,passid,sessionnumber,passnum from InfAbandonedMap
	where
	((passid='1' and sessionnumber='1' and passnum='1') 
	or (passid='2' and sessionnumber='2' and passnum='1') 
	or (passid='2' and sessionnumber='2' and passnum='3')
	or (passid='1' and sessionnumber='1' and passnum='3') 
	or (passid='3' and sessionnumber='3' and passnum='1') 
	or (passid='3' and sessionnumber='3' and passnum='3')
	or (passid='4' and sessionnumber='4' and passnum='1')
	or (passid='4' and sessionnumber='4' and passnum='3')
	or (passid='4' and sessionnumber='4' and passnum='3')
	or (passid='5' and sessionnumber='5' and passnum='1')
	or (passid='5' and sessionnumber='5' and passnum='3'))
	and testend between (trunc(add_months(sysdate,$_mon),'mm')+8/24) and (trunc(add_months(sysdate,$_mon+1),'mm')+8/24)
	)a left join InfControl b on  a.keynumber=b.keynumber)
	where (substr(lot, 1, 1) in (select Pattern from LotPattern ) or substr(lot, 1, 2) in (select Pattern from LotPattern)) order by TestEnd desc";
	my $sth=$dbh->prepare($sql);
	$sth->execute();
	$sth->bind_columns(
		undef,\$testid,\$testtime,\$passid,\$sessionnumber,\$passnum,\$device,\$lot,\$slot
	);
	my $obj=shift_block->new();
	$obj->sel_card("/exec/apps/bin/lib/perl5/shift_card/shift_card$current_year");
	while($sth->fetch()){
		my $shift=$obj->getshift($testtime);
		my $pass=$passid.$sessionnumber.$passnum;
		if (defined $unique->{$testid}->{$lot}->{$device}->{$pass}->{$slot}) {
			next if ($testtime <= $unique->{$testid}->{$lot}->{$device}->{$pass}->{$slot}) 
		}
		$unique->{$testid}->{$lot}->{$device}->{$pass}->{$slot}=$testtime;
		my $log={};
#	print localtime($testtime)."="."$shift\n";
		if($testid=~ /b3(.*)[0-9]{2}$/){
			$tester=$1;
		}else{
			$tester=$tester_alis{$testid};
			if($tester=~ /b3(.*)[0-9]{2}$/){
 	   			$tester=$1;
	       		}else{
				$tester=$testid;	
			}
		}
		if (defined $unit->{$tester}->{$shift}){
			$unit->{$tester}->{$shift}+=1;
#print "$tester:".$unit->{$tester}."\n";
		}else{ 
			$unit->{$tester}->{$shift}=1;
#print "$tester:".$unit->{$tester}."\n";
		}	
		$log->{PASS}=$pass;
		$log->{TESTER}=$testid;
		$log->{TIME}=strftime('%F %T',localtime($testtime));
		$log->{DEVICE}=$device;
		$log->{LOT}=$lot;
		$log->{SHIFT}=$shift;
		$log->{slot}=$slot;
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($testtime);	
		if ($mday <= 15){
			push @Tester_log_1,$log;	
		}else{
			push @Tester_log_2,$log;
		}
	};
	$sth->finish();
	$dbh->disconnect;
	foreach my $platform (keys %$unit){
		$ref_platform=$unit->{$platform};
        	foreach my $shift(keys %$ref_platform){
                	$unit->{$platform}->{SUM}=$unit->{$platform}->{SUM}+$unit->{$platform}->{$shift};
        #       print "SUM-$platform=".$unit->{$platform}->{SUM}."\n";
                	$unit->{SUM_Tester}->{$shift}=$unit->{SUM_Tester}->{$shift}+$unit->{$platform}->{$shift};
#               print "SUM-$shift-$platform=".$unit->{SUM}->{$shift}."\n";
        	}
		$unit->{SUM_Tester}->{SUM}=$unit->{SUM_Tester}->{SUM}+$unit->{$platform}->{SUM};
	}
	return $unit;
}

sub Promis_FOI_output{
	my $unit=shift;
	my $dbh=DBI->connect(&getconn('tjn','promis','read')) or die $@;
	my $sql="select (trackintime-to_date('1970-1-1 08:00:00','yyyy-mm-dd hh24:mi:ss'))*24*60*60 ,trackinmainqty,lotid,partname from bat3ptorrent.hist where (stage='9700-FOI' or stage='970W-FOI') and trackintime between (trunc(add_months(sysdate,$_mon),'mm')+8/24) and (trunc(add_months(sysdate,$_mon+1),'mm')+8/24) order by trackintime";
	my $sth=$dbh->prepare($sql);
	$sth->execute();
	$sth->bind_columns(
        	undef,\$starttime,\$qty,\$lotid,\$partname
	);
        my $obj=shift_block->new();
        $obj->sel_card("/exec/apps/bin/lib/perl5/shift_card/shift_card$current_year");
	my $unique={};
	while($sth->fetch()){
		my $log={};
        	my $shift=$obj->getshift($starttime);
		if (defined $unique->{$partname}->{$lotid}->{$shift}){
			next if ($unique->{$partname}->{$lotid}->{$shift} <= $starttime);
		}
		$unique->{$partname}->{$lotid}->{$shift}=$starttime;
        	if (defined $unit->{'PROMIS FOI'}->{$shift}){
                	$unit->{'PROMIS FOI'}->{$shift}+=$qty;
#print "FOI:".$unit->{FOI}->{$shift}."\n";
        	}else{
                	$unit->{'PROMIS FOI'}->{$shift}=$qty;
        	}
		$unit->{'PROMIS FOI'}->{SUM}+=$qty;
		$log->{LOT}=$lotid;
		$log->{TIME}=strftime('%F %T',localtime($starttime));
		$log->{DEVICE}=$partname;
		$log->{QTY}=$qty;
		$log->{SHIFT}=$shift;
		push @FOI_promis_log,$log;
	};
	$sth->finish();
	$dbh->disconnect;
	return $unit;
}

sub Genesis_FOI_output{
	my $unit=shift;
	my $dbh=DBI->connect(&getconn('tjn','genesis','read')) or die $@;
	my $sql="select (PROCESS_START_TIME-to_date('1970-1-1 08:00:00','yyyy-mm-dd hh24:mi:ss'))*24*60*60,devc_number,wafr_number from GenStaging.wlot_step_hists  where STEP_NAME='PROBE-FOI' and process_start_time between (trunc(add_months(sysdate,$_mon),'mm')+8/24) and (trunc(add_months(sysdate,$_mon+1),'mm')+8/24) order by PROCESS_START_TIME";
	my $sth=$dbh->prepare($sql);
	$sth->execute();
	$sth->bind_columns(
        	undef,\$starttime,\$partname,\$lotid
	);              
        my $obj=shift_block->new();
        $obj->sel_card("/exec/apps/bin/lib/perl5/shift_card/shift_card$current_year");
	my $unique={};
	while($sth->fetch()){
        	my $log={};
        	my $shift=$obj->getshift($starttime);
                if (defined $unique->{$partname}->{$lotid}->{$shift}){
                        next if ($unique->{$partname}->{$lotid}->{$shift} <= $starttime);
                }
                $unique->{$partname}->{$lotid}->{$shift}=$starttime;
        	if (defined $unit->{'SFC BG+INK FOI'}->{$shift}){
                	$unit->{'SFC BG+INK FOI'}->{$shift}+=1;
#print "FOI:".$unit->{FOI}->{$shift}."\n";
        	}else{
                	$unit->{'SFC BG+INK FOI'}->{$shift}=1;
        	}
        	$unit->{'SFC BG+INK FOI'}->{SUM}+=1;
        	$log->{LOT}=$lotid;
        	$log->{TIME}=strftime('%F %T',localtime($starttime));
        	$log->{DEVICE}=$partname;
        	$log->{SHIFT}=$shift;
        	push @FOI_genesis_log,$log;
	};
	$sth->finish(); 
	$dbh->disconnect;
	return $unit;
} 

sub FOI_output{
	my $unit=shift; 
	$unit=&Promis_FOI_output($unit);
	$unit=&Genesis_FOI_output($unit);
	my @FOI=('PROMIS FOI','SFC BG+INK FOI');
	my @shift=('A','B','C','D');
	foreach my $FOI (@FOI){
		foreach my $shift (@shift){	
			$unit->{SUM_FOI}->{$shift}=$unit->{$FOI}->{$shift}+$unit->{SUM_FOI}->{$shift};
		}
		$unit->{SUM_FOI}->{SUM}=$unit->{SUM_FOI}->{SUM}+$unit->{$FOI}->{SUM};
	}
	return $unit;
}

sub genexcel{
	my $ref=shift;
	my %unit=%$ref;
	my $sheet_name="shift_report-$current_year-$last_mon";
	my $xls_obj = new Spreadsheet::WriteExcel("$report_pathdir/$xls_file") or return $!;
	my $format_normal=$xls_obj->add_format();
	my $format_title=$xls_obj->add_format();
	my $sheet=$xls_obj->add_worksheet($sheet_name);
	$format_title->set_align('center');
	$format_title->set_bold();
	$format_normal->set_align('center');
	my $sheet_log_Tester_1=$xls_obj->add_worksheet('Tester_LOG_1');
	my $sheet_log_Tester_2=$xls_obj->add_worksheet('Tester_LOG_2');
	my $sheet_log_FOI_promis=$xls_obj->add_worksheet('PROMIS FOI_LOG');
	my $sheet_log_FOI_genesis=$xls_obj->add_worksheet('BG+INK FOI_LOG');
##sort row title####
	$ref_j750=$unit->{j750};
	my @title=sort (keys %$ref_j750);
##sort colounm title####
	my @content_tmp=sort (keys %unit);
	my @content;
	foreach my $string (@content_tmp){
		next if ($string eq 'SUM_Tester');
		next if ($string eq 'PROMIS FOI');
		next if ($string eq 'SFC BG+INK FOI');
		next if ($string eq 'SUM_FOI');
		push @content,$string;
	}  
	push @content,'SUM_Tester';
	push @content,'';
	push @content,'PROMIS FOI';
	push @content,'SFC BG+INK FOI';
	push @content,'SUM_FOI';
###report#########
	unshift @title,'PLATFORM';
	for (my $i=0;$i<@title;$i++){
		$sheet->write(0,$i,$title[$i],$format_title);
        	for(my $j=0;$j<=@content;$j++) {
			if ($i==0){
				$sheet->write(1+$j,0,uc($content[$j]),$format_title);
			}else{
                		$sheet->write(1+$j,$i,$unit->{$content[$j]}->{$title[$i]},$format_normal);
			}
        	}
	} 
	$sheet->set_column('A:A',20);
#Tester_log#
	for (my $i=0;$i<@Tester_log_1;$i++){
        	my $j=0;
        	my $ref=$Tester_log_1[$i];
        	foreach my $key (sort keys %$ref){
                	$sheet_log_Tester_1->write($i,$j,$Tester_log_1[$i]->{$key});
                	$j++;
        	}
	}
	$sheet_log_Tester_1->set_column('A:A',20);
	$sheet_log_Tester_1->set_column('B:B',20);
	$sheet_log_Tester_1->set_column('F:F',20);
	for (my $i=0;$i<@Tester_log_2;$i++){
        	my $j=0;
        	my $ref=$Tester_log_2[$i];
        	foreach my $key (sort keys %$ref){
                	$sheet_log_Tester_2->write($i,$j,$Tester_log_2[$i]->{$key});
                	$j++;
        	}
	}
	$sheet_log_Tester_2->set_column('A:A',20);
	$sheet_log_Tester_2->set_column('B:B',20);
	$sheet_log_Tester_2->set_column('F:F',20);
#FOI_promis_log###
	for (my $i=0;$i<@FOI_promis_log;$i++){
		my $j=0;
		my $ref=$FOI_promis_log[$i];
		foreach my $key (sort keys %$ref){
			$sheet_log_FOI_promis->write($i,$j,$FOI_promis_log[$i]->{$key});
			$j++;
		}
	}
	$sheet_log_FOI_promis->set_column('A:A',20);
	$sheet_log_FOI_promis->set_column('B:B',20);
#FOI_genesis_log###
	for (my $i=0;$i<@FOI_genesis_log;$i++){
        	my $j=0;
        	my $ref=$FOI_genesis_log[$i];
        	foreach my $key (sort keys %$ref){
                	$sheet_log_FOI_genesis->write($i,$j,$FOI_genesis_log[$i]->{$key});
                	$j++;
        	}
	}
	$sheet_log_FOI_genesis->set_column('A:A',20);
	$sheet_log_FOI_genesis->set_column('B:B',20);
	return 1;
}

sub sendmail{
        $msg = MIME::Lite->new(
                From => 'output_report system',
                To => "$mail_list",
                Type => 'multipart/mixed',
                Subject => "Output_Report $current_year-$last_mon"
                );
                $msg->attach(
                Type => 'TEXT',
                Data => "Hello:\n\n".
			"This is Year:$current_year Month:$last_mon Output-Report\n\n".
                        "Please review with attachement \n\n\n".
                        "This is an automatic email sent by the  system, please do not reply."
        );
        # Attachment
        $msg->attach(
                Type => 'auto',
                Path => "$report_pathdir/$xls_file",
                Filename => "$xls_file",
                Disposition => 'attachment'
        );
        $msg->send or return $!;
return 1
}
#print Dumper($unit);
