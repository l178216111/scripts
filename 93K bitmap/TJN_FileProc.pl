#!/usr/local/bin/perl

require 5.000;
use POSIX qw(strftime);    # perl5 builtin

# ------------------------------------------------------------------------ #
# OHP_DataProc
#
#	Manages transfer of files from tester spool directories
#  	to external transfer points.
#
#	Richard Daniel, Austin Test Data Systems	03/08/2004
#
#
# ------------------------------------------------------------------------ #

$RCS =
q{$Header: /exec/apps/src/cron/bin/RCS/OHP_FileProc.pl,v 1.11 2011/01/25 15:36:39 probe Exp $};

$NFS_SLEEP_TIME = 60;        #seconds
$NFS_TIMEOUT    = 60 * 5;    #seconds

$GZIP = '/bin/gzip';
-x "$GZIP" or die "Can't execute gzip from $GZIP.\n";

BEGIN {

	$me = ( reverse split '/', $0 )[0];    # basename $0
	$myself = ( split '\.', $me )[0];      # no extension

	$HOME = '/exec/apps/bin/cron';

	#  $HOME        = '/exec/apps/src/cron';

	$CONFIG = "$HOME/bin/.$myself";
	$CONFIG = "$HOME/.$myself" unless -r $CONFIG;
	$LOGDIR = "/data/probe_logs/cron/";
	$LOGDIR .= $ARGV[1] if $ARGV[1];

	-r $CONFIG or die "$me - can't locate config file $CONFIG\n";
	-d $LOGDIR or die "$me - can't locate log dir $LOGDIR\n";
	-w _       or die "$me - can't write into log dir $LOGDIR\n";

	eval { $xfers = do $CONFIG };
	$@ and die "$me - error executing config file $CONFIG!";

	unshift @INC, "$HOME/lib";    # custom modules
}

use logit qw( openlog closelog );    # logit.pm logging module

sub stamp {
	logit::stamp( "$myself, $xfer, " . shift() );
}                                    # add $myself and $xfer to log stamp

## create cleanup routine in case we die early or are killed
##

sub cleanup { &cleanWorkdir; closelog; }
$SIG{__DIE__} = \&cleanup;

sub sig_handler {
	warn stamp "dying with $_[0], trying cleanup ...\n";
	&cleanup;
}
$SIG{'INT'}  = \&sig_handler;
$SIG{'QUIT'} = \&sig_handler;

##
## check for required system commands

$CP = '/bin/cp';
-x "$CP" or die "cannot locate system cp at $CP";
$LS = '/bin/ls';
-x "$LS" or die "cannot locate system cp at $LS";

##
## process transfer argument

$xfer = $ARGV[0] or die stamp "error, no transfer key argument passed\n";
defined $xfers->{$xfer} or die stamp "error, no config for key $_ in $CONFIG\n";

$date = $ARGV[1] || strftime( "%m-%d-%Y_%H:%M:%S", localtime(time) );
$start = time;
sleep 1;

## setup logging

$| = 1;
chomp( my $host = `hostname` );
$WW = strftime "%W", localtime;
$logdate = 'ww' . $WW;    # work week
openlog ">$LOGDIR/${myself}_${xfer}_${host}_${logdate}.log";

print stamp "info, processing transfer, $xfer\n";

$spool = $xfers->{$xfer}{from};    # name of source directory
-d "$spool" or die "spool dir not found : $spool\n";

$filter  = $xfers->{$xfer}{filter};     # RE pattern to filter files
$fileage = $xfers->{$xfer}{fileage};    # Time since file last modified
$limit   = $xfers->{$xfer}{limit};      # maximum files per transfer attempt

@dest = @{ $xfers->{$xfer}{to} };       # list of hashrefs of destinations
$gzip_xfer = $xfers->{$xfer}{gzip};   # flag to gzip before dist to destinations

##
##  create a working directory to allow multiple DataProc's to work on same spool

$workdir = join( '_', $spool, $xfer, $host, $$ );
mkdir $workdir or die "error, cannot mkdir $workdir : $!\n";

print stamp "info, working in $workdir\n";

##
## move files to working directory

-w "$spool" or die stamp "spool dir not writable!\n";
opendir SPOOL, $spool or die stamp "cannot opendir $spool: $!\n";

$limit or $limit = 10000;    # default files per transfer
$files = 0;

chdir $spool;
while ( $_ = readdir SPOOL ) {

	next if /^\./;                        # skip any dot files, incl . and ..
	next if ( $filter && !/$filter/ );    # if defined, use filter
	                                      # skip files < fileage minutes old
	next if $fileage && minutes_since_last_modified($_) < $fileage;

	$files++ if rename "$spool/$_", "$workdir/$_";
	last if $files >= $limit;
}

closedir SPOOL;

$files > 0
  or print stamp "info, no files to transfer\n"
  . "\tspool: $spool"
  . ( ($filter) ? "  (filter = '$filter')\n" : "\n" );

print stamp "info, working on $files files\n";

##
## transfer files to each destination

opendir WORKING, $workdir;

$transfered = 0;
$count      = 0;
while ( $file = readdir WORKING ) {

	next if $file =~ /^\.\.?$/;
	next if ( $filter && $file !~ /$filter/ );    # if defined, use filter

	$in_all_destinations = 1;

	if ( $gzip_xfer && $file !~ /\.gz$/ ) {
		system("$GZIP -f $workdir/$file");
		$file .= '.gz';
	}

	if ( !$gzip_xfer && $file =~ /\.gz$/ ) {
		system("$GZIP -df $workdir/$file");
		$file =~ s/\.gz$//;
	}

	$size = -s "$workdir/$file";

	for $dest (@dest) {

		if ( defined $dest->{'dir'} ) {

			$target = $dest->{'dir'};
			$rename = $dest->{'rename'} || 'new';

			( -d "$target" && -w _ ) or waitOnTarget($target) or do {

				warn stamp "warning, destination $target is not available...  skipping";
				$in_all_destinations = 0;
				next;
			};

			my $new_name =
			  ( $dest->{'rename'} eq 'dot' ) ? ".new.${file}" : "${file}.new";

#			print stamp "$CP -p $workdir/$file $target/${new_name}\n";
			print stamp "$CP $workdir/$file $target/${new_name}\n";

#			system("$CP -p $workdir/$file $target/${new_name}");
			system("$CP $workdir/$file $target/${new_name}");

			unless ( -s "$target/${new_name}" == $size ) {

				unlink "$target/${new_name}";
				$in_all_destinations = 0;
				print stamp "failed, $workdir/$file to $target\n";

			}
			else {

				rename "$target/${new_name}", "$target/$file";
				chomp( $ls = `$LS -l $target/$file` );
				print stamp "transfered, $ls\n";
			}

		}
		elsif ( defined $dest->{'proc'} ) {

			my $home = $dest->{'home'} || $HOME;
			$cmd = qq($home/$dest->{'proc'} $workdir/$file);

			print stamp "executing, $cmd\n";
			print `$cmd`;
			if ($?) {
				warn stamp "warning, process execution error ($?) on file $file for $cmd";
				$in_all_destinations = 0;
				next;
			}
			else {
				print stamp "processed, $file with $cmd\n";
			}

		}
		elsif ( defined $dest->{'fileproc'} ) {

			# ie W06L93S_D12345.1A_1_01.stdf
			$filespec = $dest->{'filespec'}
			  || '_?([A-Z][0-9A-Z]+[A-Z][0-9]{2}[A-Z])_([A-Z]{1,2}[0-9]{5}\.[0-9]+[A-Z])_(\d)_(\d+).(.+)';

			$file =~ /$filespec/ or do {

				warn stamp "warning, filname match /$filespec/ failed for file $file";
				$in_all_destinations = 0;
				next;
			};
			( $Device, $Lot, $Pass, $Waf, $extensions ) =
			  ( $1, $2, $3, $4, $5 );

			my $home = $dest->{'home'} || $HOME;
			$cmd = qq($home/$dest->{'proc'} $Device $Lot $Pass $Waf $workdir/$file);

			print stamp "executing, $cmd\n";
			print `$cmd`;
			if ($?) {
				warn stamp "warning, process execution error ($?) on file $file for $cmd";
				$in_all_destinations = 0;
				next;
			}
			else {
				print stamp "processed, $file with $cmd\n";
			}

		}
		else {
			warn stamp "warning, no 'dir' or 'proc' or 'fileproc' destination for entry in xfer $xfer";
		}

	}    # for $dest

	$count++;

	if ($in_all_destinations) {

		$transfered++;
		unlink "$workdir/$file" unless defined $dest->{'proc'};
		print stamp sprintf( "completed, (%d/%d) %s\n", $count, $files, $file );
	}
	else {

		print stamp sprintf( "partial, (%d/%d) %s\n", $count, $files, $file );
	}

}    # while $file

closedir WORKING;

$rate = $transfered / ( time - $start );
print stamp sprintf
  "info, sent %d/%d files at effective rate of %0.1f files/sec\n",
  $transfered, $files, $rate;


for $dest (@dest) {
	if ( defined $dest->{'dir'} && defined $dest->{'final_proc'}) {
		my $script = $dest->{'final_proc'};
		my $dest_dir = $dest->{'dir'};
		my $part = $dest->{'part'};
		if ($part =~ /^\s+$/) {
			$part = "default";
		}
		
		print stamp "executing script $script\n";
		
		my $cmd = qq($script $dest_dir $part);
		print `$cmd`;
		if ($?) {
			warn stamp "warning, process execution error ($?) for $cmd, ErrorCode $@";
		}
		else {
			print stamp "processed, cmd $cmd\n";
		}
	}
}


##
## cleanup

&cleanWorkdir;
&closelog;

exit 0;

#
# move any files left back to spool
#

sub cleanWorkdir {

	return unless -d "$workdir";
	opendir WORKING, $workdir;

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

#
# wait for directory to be avilable
#

sub waitOnTarget {

	my $dir = shift;

	my $start = time;
	my $elapsed;

	if ( -e "$dir" && !-d _ ) {

		warn stamp "warning, $dir is not a directory!\n";
		return 0;
	}

	while ( !-d "$dir" and !-w _ ) {

		if ( ( $elapsed = time - $start ) > $NFS_TIMEOUT ) {

			print stamp "warning, timed out waiting for $dir\n";
			return 0;
		}

		print stamp "info, waiting for $dir ... ($elapsed elapsed)\n";
		sleep $NFS_SLEEP_TIME;
	}

	return 1;
}

sub minutes_since_last_modified {
	my $file                  = shift;
	my $now                   = time();
	my $file_secs_since_epoch = ( stat $file )[9];
	return ( ( $now - $file_secs_since_epoch ) / 60 );
}
