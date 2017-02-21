#! /usr/local/bin/perl5

#########################################################################
#                                                                       #
# Program:      STDFProc.pl                                      	#
#                                                                       #
# Description:  This script is called for each wafer transfered.        #
#               It copies the STDF file for this wafer to DBOX.		#
#                                                                       #
# Usage:        STDFProc.pl 0 1 2 3                            		#
#                       Where 0 = Device Type                           #
#                       Where 1 = Lot Number                            #
#                       Where 2 = Pass Number                           #
#                       Where 3 = Wafer Number                          #
#                                                                       #
# Created:      Richard Daniel  08/14/2005                              #
#                                                                       #
# Revisions:    See RCS history (rlog).                                 #
#                                                                       #
#########################################################################
# change the istar patt configfile to master_info_file by Liuzx 2016mar15
# istar config file:/exec/apps/probe_config/master_info_file            #
# example:KE01N21B{                                                     #
#        STDF_istar:yes                                                 #
#       }                                                               #
# yes:copy the istar STDF to /data/transfer/loader/Istar/STDF		#
#########################################################################


use POSIX qw(strftime);
use lib "/exec/apps/bin/lib/perl5";
use INFAnalysis;
$RCS = q{$Id: STDFProc.pl,v 1.2 2006/02/22 07:10:37 probe Exp $};

## Load Config, if not already loaded

$EOW_HOME='/custom/EOW';
require "$EOW_HOME/config_eow.pl" unless $EOW_CONFIG;
$ISTAR_STDF_FOLDER='/data/transfer/loader/Istar/STDF';
my $master_info_file='/exec/apps/probe_config/master_info_file';
#$ISTAR_DEVICE_FILE='/exec/apps/bin/evr/istar/AOL_layer.txt';
#$ISTAR_DEVICE_FILE='/exec/apps/bin/evr/istar/istar_devices.txt';
$MONITOR_STDF_FILE = "/exec/apps/bin/evr/Monitor_missing_stdf/monitor_stdf.txt";

$time = strftime('%Y%m%d-%H%M%S', localtime(time()));


## set flag file and check
$MISS_STDF_FILE = "/var/tmp/miss_stdf";
$STDF_FLAG_FILE = "/var/tmp/stdf_flag_found";
$NOSTDF_FLAG_FILE = "/var/tmp/nostdf_flag_found";

#if(-e $STDF_FLAG_FILE) {
#        $rm_cmd = untaint("rm $STDF_FLAG_FILE");
#        system($rm_cmd);
#}
#if(-e $NOSTDF_FLAG_FILE) {
#        $rm_cmd = untaint("rm $NOSTDF_FLAG_FILE");
#        system($rm_cmd);
#}


## Grab command line args

$Woo     = $1 if $ARGV[0] =~ /^(.+)$/;
$Lot     = $1 if $ARGV[1] =~ /^(.+)$/;
$Pass    = $1 if $ARGV[2] =~ /^(.+)$/;
$Wafer   = $1 if $ARGV[3] =~ /^(.+)$/;
$Station = $1 if $ARGV[4] =~ /^(.+)$/;
$STDF_FILE = $1 if $ARGV[5] =~ /^(.+)$/;

@Error = ();

print ("STDFProc ----> Executing for $Woo $Lot waf $Wafer at $time\n\n");
writeLog("/tmp/eow.log","STDFProc ----> Executing for $Woo $Lot waf $Wafer \n");


 ## locate STDF file for this wafer

if( $STDF_FILE ) {

   print "STDFProc =---> using STDF filename from command line: $STDF_FILE\n\n";

} else {

## look for stdf files in tester dir for this wafer

    $STDF_DIR = "$ENV{TMP_DIR}/stdf";
    opendir STDFDIR, $STDF_DIR or do {
        raiseError("Cannot locate STDF dir $STDF_DIR\n");
        exit 1;
    };

    @STDF_FILES = grep { /${Lot}_${Wafer}\..*stdf/ } readdir STDFDIR;
    closedir STDFDIR;

    @STDF_FILES = map { "${STDF_DIR}/$_" } @STDF_FILES;

    unless (@STDF_FILES) {
	#system(untaint("touch $NOSTDF_FLAG_FILE"));
        #raiseError("No STDF files found for $Lot wafer $Wafer in ${STDF_DIR}\n");
	
	unless (  -r $MISS_STDF_FILE ) {
                system(untaint("touch $MISS_STDF_FILE"));
        }	
	writeLog($MISS_STDF_FILE,"$Lot,$Wafer\n");
        $cmd = untaint("grep $Lot $MISS_STDF_FILE | wc -l");
        chomp($result = `$cmd`);
        $result =~ tr/\t //d;
        print "missing stdf file total number is(result) in fact =---> $result\n";
	
	chomp($include_flag=`grep -v '#' $MONITOR_STDF_FILE | grep -i $Woo | grep -i PASS$Pass`);
        if ( "X$include_flag" ne "X" ) {
                ($dump1, $dump2,,$dump3, $monitor_miss_count)=split('\s+', $include_flag);
                #print "milo_debug monitor_miss_count: ===> $monitor_miss_count\n";
                #print "milo_debug:dump1 ===> $dump1\n";
                #print "milo_debug:dump2 ===> $dump2\n";
                #print "milo_debug:dump3 ===> $dump3\n";

                #if ( $result >= $monitor_miss_count && $monitor_miss_count != 1 ) {
                print "missing_count is -----> $monitor_miss_count\n";
                if ( $result >= $monitor_miss_count ) {
                # no stdf file -------
                        raiseError("STDFProc --> Keeping no STDF file found on $monitor_miss_count wafers for $Lot!\n");
                        system(untaint("touch $NOSTDF_FLAG_FILE"));
                        #***********add by milo chen****************
                        #********************* delete "stdf fouond flag"*************************
                        if (  -r $STDF_FLAG_FILE ) {
                                $cmd = untaint("rm -f $STDF_FLAG_FILE");
                                print "STDFProc ----> $cmd\n";
                                print `$cmd`;
                        }
                        #*********end****************

                 } else  {
                        if ( $result == $monitor_miss_count ) {
                                raiseError("STDFProc --> No STDF file found for $Lot $Wafer!\n");
                                system(untaint("touch $NOSTDF_FLAG_FILE"));

                        #***********add by milo chen****************
                        # delete "stdf fouond flag"
                        if (  -r $STDF_FLAG_FILE ) {
                                $cmd = untaint("rm -f $STDF_FLAG_FILE");
                                print "STDFProc ----> $cmd\n";
                                print `$cmd`;
                        }
                        #*********end****************
                        }
                }
        }
        raiseError("STDFProc --> No STDF file found for $Lot wafer $Wafer in $ENV{TMP_DIR}\n");

	#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	#     new code insert end 
	#
	#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        exit 1;

    } else {
	system(untaint("touch $STDF_FLAG_FILE"));
	#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	#	add new code for missing stdf evr
	#
	#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
	
	#***********add by milo chen****************
        # delete "no stdf fouond flag"
        if (  -r $NOSTDF_FLAG_FILE ) {
                $cmd = untaint("rm -f $NOSTDF_FLAG_FILE");
                print "STDFProc ----> $cmd\n";
                print `$cmd`;
        }

        #*****************************************
        # delete missing stdf record file

        if (  -r $MISS_STDF_FILE ) {
                $cmd = untaint("rm -f $MISS_STDF_FILE");
                print "STDFProc ----> $cmd\n";
                print `$cmd`;
        }
        #*********end****************


        print "STDFProc =---> Found ".int(@STDF_FILES)." local STDF files\n";
    }
} #if

for $STDF_FILE (@STDF_FILES) {

 print ("STDFProc ----> processing $STDF_FILE\n");

 ## Move STDF to data probe archive

 $lotspec = new LotSpec($Woo, $Lot);
 $device = lc($Woo);
 $par_lot = lc($lotspec->LotID_parent);

 @stdf_stat = stat($STDF_FILE);
 $stdf_time = strftime('%Y%m%d-%H%M%S', localtime($stdf_stat[9]));

 $stdf_name = join('~', $stdf_time, $Woo, $Lot, $Wafer, $Pass).".stdf";
 $probe_stdf_file="$ENV{'ARCH_DIR'}/$device/$par_lot/stdf/$stdf_name";

 mkdir "$ENV{'ARCH_DIR'}/$device" 
	unless -d "$ENV{'ARCH_DIR'}/$device";
 mkdir "$ENV{'ARCH_DIR'}/$device/$par_lot" 
	unless -d "$ENV{'ARCH_DIR'}/$device/$par_lot";
 mkdir "$ENV{'ARCH_DIR'}/$device/$par_lot/stdf" 
	unless -d "$ENV{'ARCH_DIR'}/$device/$par_lot/stdf";

 copyfile($STDF_FILE, $probe_stdf_file);

 if (-r $probe_stdf_file ) {

  	print "STDFProc ----> $GZIP $probe_stdf_file\n";
	$cmd = untaint("$GZIP $probe_stdf_file");
	system($cmd);

	if (-r "${probe_stdf_file}.gz" ) {
	  $probe_stdf_file .= '.gz';
	  $stdf_name .= '.gz';
	} else {
	  raiseError("Error during gzip on $probe_stdf_file\n");
	}

	$cmd = untaint("ls -al $probe_stdf_file");
	chomp($ls = `$cmd`);
	writeLog($XFER_LOGFILE, "$Woo, $Lot, $Wafer, $ls\n");

  	## change uid and gid to allow rm command to work
  	#print "STDFProc ----> switching uid from $> to $< \n";
  	#print "STDFProc ----> switching gid from $) to $( \n";
  	#$egid = $);
  	#$euid = $>;
  	#$> = $<;
  	#$) = $(;

	$cmd = untaint("rm -f $STDF_FILE");
  	print "STDFProc ----> $cmd\n";
	print `$cmd`;

  	#print "STDFProc ----> switching back uid to $euid and gid to $egid\n";
  	#$> = $euid;
  	#$) = $egid;


 } else {

 	$msg="STDFProc ----> Error copying stdf file to $probe_stdf_file.\n";
 	print "$msg\n"; raiseError($msg);
 }

 ## Copy to transfer with standard name

 $rc=check_prodlot($Woo, $Lot, $Sort, $Wafer, $Station);
 if ( $rc == 1 ) {

     $dest_stdf_file="$ENV{'DBOX_DIR'}/STDF/$stdf_name";
    
     copyfile($probe_stdf_file, $dest_stdf_file);
    
     if (-r $dest_stdf_file) {
    
    	$cmd = untaint("ls -al $dest_stdf_file");
    	chomp($ls = `$cmd`);
    	writeLog($XFER_LOGFILE, "$Woo, $Lot, $Wafer, $ls\n");
    
     } else {
    
     	$msg="STDFProc ----> Error copying stdf file to $dest_stdf_file.\n";
     	print "$msg\n"; raiseError($msg);
     }
 } else {
   print "STDFProc ----> NON Prod lot. Not transfer to DBOX \n";
 }

#
# copy the file to EWM if enabled in master info
# Added by Jiandong  2009/03/26
#
print "STDFProc ---> copy the file to EWM if enabled in master info\n";

if ( $rc == 1 && $ENV{ewm_stdf} eq "yes") {
        if ( -e $ENV{'EWM_STDF_DIR'} && -w $ENV{'EWM_STDF_DIR'}) {

                print ("STDFProc =---> Copying $probe_stdf_file to $ENV{'EWM_STDF_DIR'}. \(:\>\n");

                -d  "$ENV{'EWM_STDF_DIR'}/.incoming" || system ("umask 000;mkdir $ENV{'EWM_STDF_DIR'}/.incoming");

                $cmd = untaint("umask 000;cp $probe_stdf_file $ENV{'EWM_STDF_DIR'}/.incoming/$stdf_name");
                system($cmd);

                $FN = $stdf_name;

                if ( -e "$ENV{'EWM_STDF_DIR'}/.incoming/$FN" ) {
			$cmd = untaint("ls -al $ENV{'EWM_STDF_DIR'}/.incoming/$FN");
        		chomp($ls = `$cmd`);
                    	writeLog($XFER_LOGFILE, "$Woo, $Lot, $Wafer, $ls\n");
                    	print("STDFProc =---> $Woo, $Lot, $Wafer, $ls\n");

                	$cmd = untaint("mv $ENV{'EWM_STDF_DIR'}/.incoming/$FN $ENV{'EWM_STDF_DIR'}/$FN");
                	system($cmd);
                	$cmd = untaint("$ENV{'EWM_STDF_DIR'}/$FN");
                	chmod (0666, "$cmd");
                    	print ("STDFProc =---> Copied $probe_stdf_file to $ENV{'EWM_STDF_DIR'}/$FN. \(:\>\n");
                }
                else {

                        unlink ("$ENV{'EWM_STDF_DIR'}/.incoming/$FN");
                        warning("$Woo $Lot $Wafer pass $Sort: Error copying STDF to EWM: $ENV{'EWM_STDF_DIR'}");
                }

        } else {
                raiseError("STDFProc --> EWM stdf path $ENV{'EWM_STDF_DIR'} unavailable while processing $Woo $Lot $Wafer Pass $Sort");
        }

} else {
	print ("STDFProc =---> $Woo $Lot STDF data not sent to EWM \(:\~\n");
}
# end if ewm_stdf

##copy the istar STDF to /data/transfer/loader/Istar/STDF ####

$istar_stdf_file="$ISTAR_STDF_FOLDER/$stdf_name";

#Add by Liuzx 2016 mar 15 to mv the istar config in master_info_file
##read the master config#####
my $read=INFAnalysis->new();
$read->LoadINF($master_info_file) or raiseError($!);
my $istar_flag=$read->block(uc($Woo));
if ($istar_flag ne "" && $rc == 1){
 $istar_flag=$read->block(uc($Woo))->key('STDF_istar');

if ( "$istar_flag" eq "yes" ) {

        copyfile($probe_stdf_file,$istar_stdf_file);

        if ( -r $istar_stdf_file ) {

                $cmd = untaint("ls -al $istar_stdf_file");

                chomp($ls = `$cmd`);

                writeLog($XFER_LOGFILE, "$Woo, $Lot, $Wafer, $ls\n");

        } else {

                $msg="STDFProc ----> Error copying stdf file to $istar_stdf_file.\n";

                print "$msg\n"; raiseError($msg);
        }
	}elsif($istar_flag ne "" && $istar_flag ne "yes"){
	$msg="STDFProc ----> Error reading master_info_file:part $Woo key:STDF_istar value:$istar_flag\n";
		print "$msg\n"; raiseError($msg);
	}
###end##################### 
} else {
	print ("STDFProc =---> $Woo $Lot STDF data not sent to AOL flag:$istar_flag\(:\~\n");
}
}
# end for
writeLog("/tmp/eow.log","STDFProc ----> End\n");
