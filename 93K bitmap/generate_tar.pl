#!/usr/local/bin/perl

require 5.000;
use POSIX qw(strftime);

# config part.
$FROM_DIR = $ARGV[0];
$PART = $ARGV[1];

chomp( my $host = `hostname` );

(-d $FROM_DIR) or die "Error: $FROM_DIR is not a directory!";

# start script

BEGIN {
	$me = ( reverse split '/', $0 )[0];    # basename $0
	$myself = ( split '\.', $me )[0];      # no extension

	$HOME = '/exec/apps/bin/93k_bitmap_scripts';

	$LOGDIR = "/data/probe_logs/hp93k/scanlog";
	$TO_DIR = "/data/transfer/Dbox/93k_scanlog";
#	$LOGDIR .= $ARGV[1] if $ARGV[1];

#	-r $CONFIG or die "$me - can't locate config file $CONFIG\n";
	-d $LOGDIR or die "$me - can't locate log dir $LOGDIR\n";
	-w _       or die "$me - can't write into log dir $LOGDIR\n";
	-d $TO_DIR or die "$me - can't locate log dir $TO_DIR\n";
	-w _       or die "$me - can't write into log dir $TO_DIR\n";

#	eval { $xfers = do $CONFIG };
#	$@ and die "$me - error executing config file $CONFIG!";

	unshift @INC, "$HOME/lib";    # custom modules
	chdir $HOME;
	$workdir = join( '_', 'spool' , $$ );
	mkdir $workdir or die "error, cannot mkdir $workdir : $!\n";
}

use logit qw( openlog closelog );
sub stamp {logit::stamp("$myself, ". shift() )}
sub cleanup {&cleanWorkdir;closelog;}
sub sig_handler {
	warn stamp "dying with $_[0], trying cleanup ...\n";
	&cleanup;
}
sub cleanWorkdir {

	return unless -d "$workdir";
	opendir WORKING, $workdir;
	my $spool = $HOME . "/Spool/";
	if (!-e $spool ) {
		mkdir $spool or die "error, cannot mkdir $spool : $!\n";
	} elsif (!-d $spool) {
		die "error, please check why $spool is not a directory? ";
	}
	
	$returned = 0;
	while ( $_ = readdir WORKING ) {

		next if /^\.\.?$/;    # skip . and ..

		$returned++ if rename "$workdir/$_", "$spool/$_";

	}    # while $file

	closedir WORKING;
	print stamp "info, cleanup returned $returned files to $spool\n"
	  if $returned;

	rmdir "$workdir" or warn "error, stranded working directory $workdir";
}

$SIG{__DIE__} = \&cleanup;
$SIG{'INT'}  = \&sig_handler;
$SIG{'QUIT'} = \&sig_handler;


# main programm

$start = time;
$WW = strftime "%W", localtime;
$logdate = 'WW' . $WW;
openlog ">$LOGDIR/${myself}_${host}_${logdate}.log";


$CP = '/bin/cp';
-x "$CP" or die "cannot locate system cp at $CP";
$LS = '/bin/ls';
-x "$LS" or die "cannot locate system cp at $LS";

$time = strftime("%Y-%m-%d-%H-%M-%S", localtime(time));
$time = "$time-$PART";

opendir(DIR,$FROM_DIR);
@source_files = readdir(DIR);
@source_files = grep { /\.scanlog/ } @source_files;
$len_source_files = @source_files;
close DIR;
if ($len_source_files == 0) {
	$cmd = "echo Not any file on $FROM_DIR, jump out";
	$last_long =  time - $start ;
	print stamp sprintf
	  "info, Not any file on $FROM_DIR, jump out\n", $last_long;


	&cleanWorkdir;
	&closelog;

	exit 0;

} else {
	$cmd = "cd $FROM_DIR;tar -cvf $HOME/$workdir/$time.tar *.scanlog* >> $LOGDIR/${myself}_${host}_${logdate}.log "; #cd in shell to prevent a problem when tar xvf.
}
chdir $HOME;
#die "\$cmd = $cmd\n";
print stamp `$cmd`;
if ($?) {
	warn stamp "warning, process execution error ($?) for $cmd, ErrorCode $@";
#	exit 0;
}
else {
	print stamp "processed, cmd $cmd\n";
}

$size = -s "$workdir/$time.tar";

#die "\$workdir/$time.tar = $workdir/$time.tar ; \$size = $size\n";

print stamp "$CP -p $workdir/$time.tar $TO_DIR/.$time.tar\n";

system("$CP -p $workdir/$time.tar $TO_DIR/.$time.tar");

unless ( -s "$TO_DIR/.$time.tar" == $size ) {

	unlink "$TO_DIR/.$time.tar";
#	$in_all_destinations = 0;
	print stamp "failed, $workdir/$time.tar to $TO_DIR/.$time.tar\n";

}
else {

	unlink "$workdir/$time.tar";
	#remove files on $FROM_DIR;
	
#comment by JN because the location of rm command in Linux & Solaris are different and also this command can't be execute successfully.

#	-x "/usr/bin/rm" and $RM = "/usr/bin/rm";
#	-x "/bin/rm" and $RM = "/bin/rm";
#	$cmd = "cd $FROM_DIR;$RM -rf *";
#	print stamp `cmd`;
#	if ($?) {
#		warn stamp "warning, process execution error ($?) for $cmd, ErrorCode $@";
#	}
#	else {
#		print stamp "processed, cmd $cmd\n";
#	}

	opendir FROM_DIR, $FROM_DIR;
	print stamp "info, cleanup files on $FROM_DIR\n";
	$returned = 0;
	while ( $_ = readdir FROM_DIR ) {

		next if /^\.\.?$/;    # skip . and ..

		unlink "$FROM_DIR/$_";

	}    # while $file
	
	print stamp "info, cleanup files on $FROM_DIR done\n";
	closedir FROM_DIR;	

	rmdir "$FROM_DIR" or warn "error, stranded working directory $FROM_DIR";
	mkdir $FROM_DIR;

	print stamp "renaming $TO_DIR/.$time.tar to $TO_DIR/$time.tar\n";
	rename "$TO_DIR/.$time.tar", "$TO_DIR/$time.scanlog.tar" or die "Can't rename $TO_DIR/.$time.tar to $TO_DIR/$time.scanlog.tar !!! reason $! $@";
	chomp( $ls = `$LS -l $TO_DIR/$time.scanlog.tar` );
	print stamp "transfered, $ls\n";
	
}

$last_long =  time - $start ;
print stamp sprintf
  "info, sent files at effective rate of %0.1f sec\n", $last_long;


&cleanWorkdir;
&closelog;

exit 0;















