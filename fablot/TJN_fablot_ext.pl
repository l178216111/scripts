#!/usr/local/bin/perl

unless( $ENV{'LD_PRELOAD'} ) {
  $ENV{'LD_PRELOAD'} = '/lib/libthread.so.1';
  exec $0, @ARGV;
}

  $me = (reverse split '/', $0)[0];     # basename $0
  $myself = (split '\.', $me)[0];       # no extension
## libraries

  use POSIX qw(strftime);		# for date stamps
  use DBI;				# for Oracle access

  use lib '/exec/apps/bin/lib/perl5';
  use LotSpec;				# for lot number validation

  use lib '/exec/apps/bin/cron/lib';
  use logit qw( openlog closelog );     # logit.pm logging module

  sub stamp { logit::stamp("$myself, ". shift() ) }

  $LOGDIR       = "/data/probe_logs/fablot_ext";
  -d $LOGDIR    or die "$me - can't locate log dir $LOGDIR\n";
  -w _          or die "$me - can't write into log dir $LOGDIR\n";

  sub cleanup { &cleanWorkdir; closelog; }
  $SIG{__DIE__} = \&cleanup;

#
# start logging
#
  $|=1; 						# don't use data buffer.

    $logdate = 'ww'. strftime "%W", localtime;          # work week
    openlog ">$LOGDIR/${myself}_${logdate}.log"		# log name : TJN_fablot_ext_ww17.log
        or die "$me - cannot log to $LOGDIR!\n";

## globals

  $max_age  =  24 * 3600;			# 24 hours in seconds
  $max_date = timestamp(time - $max_age);	# date filter for non-PROMIS lots

  $fablot_dir = '/exec/apps/probe_config/fablot_ext';
#  $fablot_dir = '/exec/apps/probe_config/fablot_ext/sue/new';
  $fablot_file_ig  = "$fablot_dir/fablot.txt";
  $fablot_file_ink = "$fablot_dir/fablot_ink.txt";
  $fablot_file_ocr = "$fablot_dir/fablot_ocr.txt";
  $fablot_file_ext = "$fablot_dir/fablot_ext.txt";

#  $ENV{'ORACLE_HOME'} = '/opt/oracle/product/8.1.7.4';

  $ENV{ORACLE_HOME} = "/u01/data/product/8.1.6" if not defined $ENV{ORACLE_HOME};
  $ENV{PATH} = "/u01/data/product/8.1.6/bin:$ENV{PATH}";
  $ENV{LD_PRELOAD} = "/lib/libthread.so.1";
  $ENV{TNS_ADMIN} = "/exec/apps/tools/oracle"; # tnsnames.ora
  $ENV{ORACLE_SID} = "tjnptor";

  $ENV{NLS_DATE_FORMAT} = $ENV{NLS_DATE_FORMAT} || 'MM-DD-YYYY HH24:MI:SS';
  @torrent = ('dbi:Oracle:tjnptor','probe','probeappsweb');

  $FoundryID_spec = q/^([A-Z0-9]{2})([A-Z])(.+)$/;

  %fablot = () ;
  $lotspec = new LotSpec();

  $dbh = DBI->connect(@torrent, {AutoCommit=>0})
        or die "Database connection not made: $DBI::errstr";

  $dbh->do("alter session set NLS_DATE_FORMAT = '$ENV{NLS_DATE_FORMAT}'");


##
## read in existing fablot file
##

for $fb ( $fablot_file_ig, $fablot_file_ext ) {

  print "Searching existing $fb ...\n";

  unless ( open(IN, "$fb") )  {
	warn "No exising fablot file $fb\n";
	next;
  } else {

    $count = 0;
    while (<IN>) {

        ($lotid, $partname, $fabid, $source, $time, 
	 $scribe, $prodarea, $location, $stage, $ldt_year) = split;

        $lotspec->LotID($lotid);
        next unless $lotspec->LotID_valid;      # skip lines w/o lot info

	$fabid = 'NULL'		unless $fabid;

	$tag = 'FABLOT';
	$tag = 'FABEXT' 	if $fb eq $fablot_file_ext;
	$source = $tag		unless $source eq "ADDLOT";

	$time   = timestamp(time)		unless $time;
	$scribe = $lotspec->LotID_scribe('xx', $fabid) || "NULL"; 

	$prodarea  = 'NULL'		unless $prodarea;
	$location  = 'NULL'		unless $location;
	$stage     = 'NULL'		unless $stage;
	$ldt_year  = 'NULL'		unless $ldt_year;

        $fablot{$lotid} = [ $lotid, $partname, $fabid, $source, $time, 
			    $scribe, $prodarea, $location, $stage, $ldt_year ];
#	print "   ".join("\t", @{$fablot{$lotid}})."\n";
 	$count++;
    }
    close IN;

    print "  found $count lots in $fb\n";
  }
}

## 
## filter non-PROMIS lots by $max-date
##

  print "Filtering old entries from fablot files ...\n";

  $deleted = 0;
  for $key ( keys %fablot ) {

   $source = @{ $fablot{$key} }[3];	# source is 4th col
   $stamp  = @{ $fablot{$key} }[4];	# date stamp is 5th col

   next if $stamp ge $max_date;

   print "\t". join("\t", @{$fablot{$key}}) ."\n";
   delete $fablot{$key}; 
   $deleted++;
 }
	
 print "  deleted $deleted lots.\n";

##
## connect to torrent (PROMIS mirror)
##

  print "Pulling PROMIS lots ...\n";

  $cmd = q{
	select 	ACTL.LOTID, ACTL.PARTNAME, ACTL.SUPPLIERBATCHID, 
	        ACTL.PRODAREA, ACTL.LOCATION, ACTL.STAGE, ACTLP.PARMVAL,
		CATG.CATEGORY
	from 	BAT3PTORRENT.ACTL ACTL, BAT3PTORRENT.ACTLLOTPARMCOUNT ACTLP, BAT3PTORRENT.CATG CATG 
	where (	
		ACTL.PRODAREA     = 'BAT3' 	or
	        ACTL.LOCATION	  in ('WAFER_CAGE', 'TEST_PROBE', 'PROBE_FOI')
	      ) and
	        ACTL.COMCLASS	    in ('W', 'X') and 
		SUBSTR(LOTTYPE,1,1) in ('P','E')  and
		ACTLP.LOTID(+)    = ACTL.LOTID and
		ACTLP.PARMNAME(+)    = '$LDT_YEAR' and
		CATG.CATEGORYTYPE = 'P' and 
		CATG.CATGNUMBER = '24' and 
		CATG.PARTPRCDNAME = ACTL.PARTNAME and 
		CATG.PARTPRCDVERSION = ACTL.PARTVERSION 
  };

  $sth=$dbh->prepare($cmd) 	 or die "DBI prepare error: $DBI::errstr";
  $sth->execute 		 or die "DBI execute error: $DBI::errstr";
  $res = $sth->fetchall_arrayref or die "DBI fetch error: $DBI::errstr";

  $promis = 0;
  foreach $row ( @$res ) {

	($lotid, $partname, $foundry_lot, $prodarea, $location, $stage,$ldt_year,$site) = @$row;
	$ldt_year  = 'NULL'             unless $ldt_year;
	$site = 'NULL'			unless $site;
	$LotID_site{$lotid} = $site;

        $lotspec->LotID($lotid);
        $lotspec->DevID($partname);
	next unless $lotspec->DevID_valid;

	$promis++;
	$foundry_id = FoundryID_lotid($foundry_lot);
	$scribe = $lotspec->LotID_scribe('xx', $foundry_id) || "NULL";

	$fablot{$lotid} = [ $lotid, $partname, $foundry_id, "PROMIS", timestamp(time()), 
			    $scribe, $prodarea, $location, $stage, $ldt_year ];

#	print "   ".join("\t", @{$fablot{$lotid}})."\n";
  }

  $sth->finish;
  $dbh->disconnect;

  print "  found $promis lots.\n";


##
## output new fablot file
##

 
  for $key ( keys %fablot ) {
    $c=0;
    for $i ( @{$fablot{$key}} ) {
	$l = length($i);
	$len[$c] = $l if $l > $len[$c];
	$c++;
    }
  }

  print "Writing new fablot files ...\n";

  $time = `date`;

  open FAB, ">$fablot_file_ig";
  open EXT, ">$fablot_file_ext";
  open INK, ">$fablot_file_ink";
  open OCR, ">$fablot_file_ocr";

  print FAB $time; 
  print EXT $time; 
  print INK $time; 
  print OCR $time; 

  $fab = $ext = $ink = $ocr = 0;

  foreach $key (sort keys %fablot ) { 

    @fablot    = @{$fablot{$key}};
    $location  = @fablot[7];		# location is 8th column

    $c=0; print FAB join("\t", (map { sprintf("%-$len[$c++]s", $_) } @fablot[0]), $fablot[1] )."\n";
    $fab++;

    $c=0; print EXT join("\t", (map { sprintf("%-$len[$c++]s", $_) } @fablot[0..$#fablot-1]), $fablot[$#fablot] )."\n";
    $ext++;

    if( uc($location) eq 'GRIND' ) {
      $c=0; print INK join("\t", (map { sprintf("%-$len[$c++]s", $_) } @fablot[0]), $fablot[1] )."\n";
      $ink++;
    }

    $c=0; print OCR join("\t", (map { sprintf("%-$len[$c++]s", $_) } @fablot[0..2]), $fablot[$#fablot] )."\n";
    $ocr++;

  }

  print FAB "END\n";
  print EXT "END\n";
  print INK "END\n";
  print OCR "END\n";

  close FAB;
  close EXT;
  close INK;
  close OCR;

  print "    $fablot_file_ig\t $fab files\n";
  print "    $fablot_file_ext\t $ext files\n";
  print "    $fablot_file_ink\t $ink files\n";
  print "    $fablot_file_ocr\t $ocr files\n";

closelog();
exit 0;

## support routines

sub timestamp { POSIX::strftime("%Y%m%d-%H%M%S", localtime(shift)) }


sub FoundryID_lottype 	{ $_[0] =~ /$FoundryID_spec/ ? $1 : 'NULL'; }
sub FoundryID_prefix 	{ $_[0] =~ /$FoundryID_spec/ ? $2 : 'NULL'; }
sub FoundryID_lotid	{
	my $FoundryID_get = $_[0];
	my $prefix_get = uc(substr($FoundryID_get, 2, 2));
	#print "prefix_get: $prefix_get\n";

	#### modified by Jiandong on Sep/01/2009   ######
        #if ( $lotid =~ /^NE/ ) {
        #       $Site_get = system("/exec/apps/bin/fablot_ext/Lot2Site.pl $lotid");
        #}else{
        #       $Site_get = '';
        #}
        #####################################

        $Site_get = $LotID_site{$lotid};
	
	### added by Jiandong on Dec/23/2009    ####
	$PREFIX_TSMC = 'PA PB PG PN CV DQ PC PF PP PH PW';
        @PREFIX_TSMC_ARRAY = split(/\s+/,$PREFIX_TSMC);

	if($prefix_get eq "MD"){
                $FoundryID_return = substr($FoundryID_get, 2, 7);
        }elsif(grep {$_ eq $prefix_get} @PREFIX_TSMC_ARRAY) {
		if($Site_get eq "TSMC"){
			$FoundryID_front = substr($FoundryID_get, 3, 1);
			$FoundryID_back = substr($FoundryID_get, 5, 5);
			$FoundryID_return = join("", $FoundryID_front, $FoundryID_back);
                }elsif($Site_get eq "MOS12") {
			$FoundryID_front = substr($FoundryID_get, 3, 1);
                        $FoundryID_back = substr($FoundryID_get, 4, 5);
                        $FoundryID_return = join("", $FoundryID_front, $FoundryID_back);
		}else{
			$FoundryID_get =~ /$FoundryID_spec/;
			$FoundryID_return = $3;
		}
		#print "F: $FoundryID_return\n";
        	 }elsif($Site_get eq "UMC"){
                	 # for UMC                  
                  	 $FoundryID_return = "UMC-".substr($FoundryID_get, 4, 5);
         	 }elsif($Site_get eq "CSM7"){
      		 # for CSM7                 
      		$FoundryID_return = "CSM7-".substr($FoundryID_get, 2, 6);
         	}else{
    		$FoundryID_return = "NULL";
     }

	return $FoundryID_return;
}
