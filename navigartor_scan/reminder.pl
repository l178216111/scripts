#!/usr/local/bin/perl5
#################################################################
#Author:zhaoxin.liu
#Usage:reminder user to confirmed navigator value 
################################################################
use lib '/exec/apps/bin/lib/perl5';
use Data::Dumper;
use DBI;
use dbconn;
use MIME::Lite;
use POSIX;
$ENV{'TNS_ADMIN'} = '/exec/apps/tools/oracle';
$maillist='bo.zhong@nxp.com,xiaofeng.liang@nxp.com,ruiyu.liu@nxp.com';
#$maillist='zhaoxin.liu@nxp.com';
$cclist='zhaoxin.liu@nxp.com';
my %result;
my $time=time()-3600*24;
my $dbh=DBI->connect(&getconn('tjn','probeweb','readwrite')) or return $!;
my $sql=qq{select setup,part,param,origin_value,current_value,update_date from navigator_setup_scan where status='pending' and update_date>='$time'};
my $sth = $dbh->prepare($sql) or die $!;
$sth->execute() or die $!;
$sth->bind_columns(undef,\$setup,\$part,\$param,\$origin_value,\$current_value,\$update_date);
while ( $sth->fetch() ) {
	$result{$setup}{$part}{$param}{origin_value}=$origin_value;
	$result{$setup}{$part}{$param}{current_value}=$current_value;
	$result{$setup}{$part}{$param}{update_date}=strftime('%F %T',localtime($update_date));
}
$dbh->disconnect() or die $!;
if (%result){
	my $text= Dumper(\%result);
	&send_mail($text);
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

