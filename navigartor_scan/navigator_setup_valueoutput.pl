#!/usr/local/bin/perl5
use File::Copy;
use MIME::Lite;
use POSIX;
my $dir_setups='/floor/data/setups/';
my $home="/probeeng/webadmin/cgi-bin/Navigator_Validation";
my $time=time();
my $fre=1;#excute frequency
die "Can't locate $dir_setups" unless (-e $dir_setups);
my @dir_scan_setups=('P8_INK_2008','P8_Flex_2008','P12_Flex_2008','P8_2008','P8_HP93K_2006','P8_J750_2010','P8_LTK1_2008');
$maillist='bo.zhong@nxp.com,xiaofeng.liang@nxp.com';
$cclist='zhaoxin.liu@nxp.com';
foreach my $platform (@dir_scan_setups){
	opendir(SETUPDIR,$dir_setups.$platform);
	my @setups=grep { $_ ne '.' and $_ ne '..' } readdir SETUPDIR;
	close SETUPDIR;
	foreach my $setup(@setups){
		my $path_setup="$dir_setups$platform/$setup"; #/floor/data/setups/P8_J750_2010/BH4E0M34P
		if ( !(-d $path_setup)){
			my $result=&process($path_setup);
			print $result;
		}	
	}
}
sub process{
	my $setup_new=shift;
	my $result;
	my @tmp_string=split(/\//,$setup_new);
	my $filename=$tmp_string[@tmp_string-1];
	my $setupname=$tmp_string[@tmp_string-2];
	open(SETUPA,"<",$setup_new) || warn $!;
	my @arry1;
	while($line=<SETUPA>){ 
		if ($line=~ /TYPE/){
			@arry1=split(/\\/,$line);
		}
	}
	close SETUPA;
	my ($maxpass,$pass);
	for(my $i=0;$i<@arry1;$i++){
#			print "$arry1[$i]\n";
			if ($arry1[$i] =~ /MPPN:(.*)/){
				$maxpass=$1;
			}
			if ($arry1[$i] =~ /MPN(\d):.*/){
				last if ( $1 > $maxpass );
#				$result.="\n$setupname  $filename\t"  if ($pass ne $1 );
				$pass=$1;
			}
			if ($arry1[$i]=~ /TTOUT\d:(.*)/){
				if ($1 ne 0){
					$result.="\n$setupname  $filename\t";
					$result.="\t$arry1[$i]";
				}
			}
#                        if ($arry1[$i] =~ /((HCE\d:.*)|(HOTP\d:.*)|(MPN\d:.*)|(TPLD\d:.*)|(TPST\d:.*))/){
#				$result.="\t$arry1[$i]";
#                        }
#			$result.="$result\t" if ($result ne "");	
	}
	return $result;
}
sub send_mail{
	my $text=shift;
        $msg = MIME::Lite->new(
                From => 'Navigator scan system',
                To => "$maillist",
                Cc => "$cclist",
                Type => 'multipart/mixed',
                Subject => "Navigator value scan"
                );
                $msg->attach(
                Type => 'TEXT',
                Data => "Hello,below setup have been changed\n\n".
			"$text".
                        "\n\nThis is an automatic email sent by the Navigator scan system, please do not reply."
        );
	$msg->send or return $@;
}
