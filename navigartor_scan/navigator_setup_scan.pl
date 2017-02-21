#!/usr/local/bin/perl5
#################################################################
#Author:zhaoxin.liu
#Usage:scan navigator value and backup
#Debug Mode will scan all value changed and will not back setup
################################################################
use File::Copy;
use Data::Dumper;
use POSIX;
use DBI;
require "/exec/apps/bin/lib/perl5/dbconn.pm";
$ENV{'TNS_ADMIN'} = '/exec/apps/tools/oracle';
my $dir_setups='/floor/data/setups/';
my $home="/probeeng/webadmin/cgi-bin/Navigator_Validation/";
my $time=time();
my $fre=3600*24*1;#excute frequency 1 day
#abandoned param
my @monitor_list=('MDOC\d','MDTE\d','TPST\d','IKT1B\d','IKTB\d');
my $fg_skip=1;
die "Can't locate $dir_setups" unless (-e $dir_setups);
my @dir_scan_setups=('P8_INK_2008','P8_Flex_2008','P12_Flex_2008','P8_2008','P8_HP93K_2006','P8_J750_2010','P8_LTK1_2008','APM90_J750_2010');
my %result;
#./navigator_setup_scan.pl 1 will only print all update value
my $debug=1 if ($ARGV[0] ==1);
print "Debug Mode will note bakeup setup file\n" if ($debug ==1);
foreach my $platform (@dir_scan_setups){
	my $dir_bak="$home/setup/$platform"; #/probeeng/webadmin/cgi-bin/navigator_scan/setup/P8_J750_2010
	if ( !(-e $dir_bak) ) {
		print "establish new setup folder:$dir_bak\n";
		mkdir $dir_bak or die $!;
	}
	opendir(SETUPDIR,$dir_setups.$platform);
	my @setups=grep { $_ ne '.' and $_ ne '..' } readdir SETUPDIR;
	close SETUPDIR;
	foreach my $setup(@setups){
		my $path_setup="$dir_setups$platform/$setup"; #/floor/data/setups/P8_J750_2010/BH4E0M34P
		if ( !(-d $path_setup)){
			if( !(-e "$dir_bak/$setup")){ 
				copy($path_setup,$dir_bak) or warn $!;
			}
			my $time_modify=(stat($path_setup))[9];
		#	print "$path_setup:$time_modify\n";
			if ($time - $time_modify <= $fre) {
				my ($result,$ref)=&cmp($path_setup,"$dir_bak/$setup",$time_modify,\%result);
				if ($result eq 'true'){
					%result=%$ref;
				}
    			}	
		}	
	}
}
&db_import(\%result);
sub db_import{
        my $result_ref=shift;
	my %result=%$result_ref;
	my $error='false';
        my $dbh_PMIS1=DBI->connect(&getconn('tjn','probeweb','readwrite')) or return $!;	
	foreach my $setup (keys %result){
		my $ref_part=$result{$setup};
		foreach my $part(keys %$ref_part){
			#/floor/data/setups/P8_J750_2010/BH4E0M34P
			my $path_setup="$dir_setups$setup/$part";
			#/probeeng/webadmin/cgi-bin/navigator_scan/setup/P8_J750_2010
			my $dir_bak="$home/setup/$setup";
			my $ref_param=$$ref_part{$part};
			foreach my $param(keys %$ref_param){
				my @sql=($setup,$part,$param,$$ref_param{$param}{old},$$ref_param{$param}{new},$$ref_param{$param}{time},"pending");
				@sql=map{s/\'/\'\'/g;$_="\'$_\'" } @sql;
				my $sql_value= join(',',@sql);
				$sql=qq{insert into navigator_setup_scan (setup,part,param,origin_value,current_value,update_date,status,id,approver) values ($sql_value,nav_sequence.nextval,'null')};
#				print "$sql\n";
				my $sth = $dbh_PMIS1->prepare($sql) or do { warn $!;$error='true'};
				$sth->execute() or do { warn $!;$error='true'};
				#bakup setupfile
                                unless ($debug ==1 or $error eq 'true'){
                                        copy($path_setup,$dir_bak) or warn $!;
                                }
			}
		}
	}
	$dbh_PMIS1->disconnect() or do { warn $!;$error='true'};
}
#print Dumper(\%result);
sub cmp{
	my ($setup_new,$setup_old,$time_modify,$ref)=@_;
	my $pattern=join('|',@monitor_list);
	my @tmp_string=split(/\//,$setup_new);
	my $filename=$tmp_string[@tmp_string-1];
	my $setupname=$tmp_string[@tmp_string-2];
	open(SETUPA,"<",$setup_new) || warn $!;
	open(SETUPB,"<",$setup_old) || warn $!;
	my @arry1;
	my @arry2;
	while($line=<SETUPA>){ 
		if ($line=~ /TYPE/){
			@arry1=split(/\\/,$line);
		}
	}
	while($line=<SETUPB>){
		if ($line=~ /TYPE/){
			@arry2=split(/\\/,$line);
		}
	}
	close SETUPA;
	close SETUPB;
	my %setup;
	for(my $i;$i<@arry1;$i++){
		$arry1[$i]=~ m/^(.*?):(.*)$/;
		my $key=&trim($1);
		my $value=&trim($2);
		$setup{$key}{'new'}=$value;
#		print "new:|$setup{$key}{new}|$key\n" if ($key =~ /TYPE/ and $filename eq 'KB00M79Z');
	}
	for(my $i;$i<@arry2;$i++){
		$arry2[$i]=~ m/^(.*?):(.*)$/;
		my $key=&trim($1);
		my $value=&trim($2);
		$setup{$key}{'old'}=$value;
#		print "old:|$setup{$key}{old}|$key\n" if ($key =~ /TYPE/ and $filename eq 'KB00M79Z');
	}
	my $diff='false';
	my %diff_unit=%$ref;
	foreach my $key (keys %setup){
		if ($key=~/($pattern)/ or $debug==1 or $fg_skip==1){
			if ($setup{$key}{'new'} ne $setup{$key}{'old'}){
				$diff='true';
=prod
				print "$key|$filename\n";
				print "old|$setup{$key}{old}|\n";
				print "new|$setup{$key}{new}|\n";
=cut
				$diff_unit{$setupname}{$filename}{$key}{new}=$setup{$key}{'new'};
				$diff_unit{$setupname}{$filename}{$key}{old}=$setup{$key}{'old'};	
				$diff_unit{$setupname}{$filename}{$key}{time}=$time_modify;
			}
		}
	}
#	print Dumper(\%setup) if ($diff eq 'true');
#	$result="$setupname  $filename    Last Modify Time: $time_modify \n".$result if ($result ne '');
	return ($diff,\%diff_unit);
}
sub trim
{
	my $string=$1 if shift=~ /^(.+)$/;
	#remove space ^@ 
	$string =~ s/(^\s+|\s+$|\n$|[^\040-\176])//g;
	#print "|$string|\n";
	if(length($string)<1){
		$string='null';
	#	print "|$string|\n";
	}
	return $string;
} 
