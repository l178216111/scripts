#! /usr/local/bin/perl5

#########################################################################
#                                                                       #
# Program:      handshake.pl                                            #
#                                                                       #
# Description:  This script is called for waiting for handshake file.   #
#                                                                       #
# Usage:        STDFProc.pl 0 1 2 3                                     #
#                       Where 0 = Device Type                           #
#                       Where 1 = Lot Number                            #
#                       Where 2 = Pass Number                           #
#                       Where 3 = Wafer Number                          #
#                                                                       #
# Created:      Yang Jiandong  02/16/2009                               #
#                                                                       #
#########################################################################

use POSIX qw(strftime);
## Load Config, if not already loaded

$EOW_HOME='/custom/EOW';
require "$EOW_HOME/config_eow.pl" unless $EOW_CONFIG;

$MAX_WAIT = 10 * 60;            # max time to wait for *.done file

## Grab command line args

$Woo     = $1 if $ARGV[0] =~ /^(.+)$/;
$Lot     = $1 if $ARGV[1] =~ /^(.+)$/;
$Sort    = $1 if $ARGV[2] =~ /^(.+)$/;
$Wafer   = $1 if $ARGV[3] =~ /^(.+)$/;
$Station = $1 if $ARGV[4] =~ /^(.+)$/;

#add by Jiang Nan for jump C lot;
if ($Lot =~ /^C/ || $Lot =~ /^KK/) {
        exit;
}
#end

my $handshake_file = "$ENV{'TMP_DIR'}/stdf/${Lot}_${Wafer}.done";

my $start = time();

writeLog("/tmp/eow.log","handshake.pl----> starting on $Woo $Lot $Wafer at $start\n");

while( ! -r $handshake_file && ($now = time()) - $start < $MAX_WAIT ) {
        print "handshake.pl ----> waiting for handshake file ... (".
                ( $MAX_WAIT - ( $now - $start) ) ." seconds left)\n";
        sleep 5;
}

unless( -r $handshake_file) {
        raiseError("Timeout waiting for handshake file $handshake_file\n");

        $logfile = "/data/probe_logs/mst_popup_err_log.log";

        open LOG, ">>$logfile" or do {
                warning("Can't open log file $logfile!\n");
                return 1;
        };
        chomp($host = `hostname`) unless defined $host;

########Kill data processing window##############
        $PIDSTR=`/usr/bin/ps -ef | grep df_to_stdf/processing_msg |grep -v "grep"`;
        print("$PIDSTR\n");
        @list=split(/ +/, $PIDSTR);
        if($list[0] eq "") {
           $pid=$list[2];
         } else {
           $pid=$list[1];
         }
         system("kill","$pid");
################################################

        print LOG ftime(time) ." $host lose data!\n";

        close LOG;

        if (-e "$EOW_HOME/MST.tcl"){
                system("$EOW_HOME/MST.tcl");
                print "PopUpWindow ----> Please restart PC!\n";
        }else {
		raiseError("Cannot find $EOW_HOME/MST.tcl \n");
	}
} else {
        print "handshake.pl ----> found handshake file $handshake_file\n";
#/data/MST_temp/stdf/EW70226.1K_25.done
        @handarray = split(/\//, $handshake_file);
#data MST_temp stdf EW70226.1K_25.done
        $handlength = @handarray;
#EW70226.1K_25.done
        $handshake_file_old = $handarray[$handlength-1];
        if ($handshake_file_old =~ /done\b/){
#EW70226 1K_25 done
                @filenamearray = split(/\./, $handshake_file_old);
#filenamelength=3
                $filenamelength = @filenamearray;
                for($count = 0; $count<100; $count++){
#EW70226.1K_25.0.done
                        $filename0 = join(".", $filenamearray[0], $filenamearray[1], "$count", $filenamearray[2]);
                        if($handlength<3){
                                $hand_filename0 = join("/", $handarray[0], $filename0);
                        }else{
#data/MST_temp
                                $hand_filename0 = join("/", $handarray[0], $handarray[1]);
#handlength=4
                                for($i=1; $i<$handlength-2; $i++){
#data/MST_temp/stdf
                                        $hand_filename0 = join("/", $hand_filename0, $handarray[$i+1]);
                                }
#data/MST_temp/stdf/EW70226.1K_25.0.done
                                $hand_filename0 = join("/", $hand_filename0, $filename0);
                        }
                        if(-e $hand_filename0){
                                unlink $hand_filename0;
                                print("delete $hand_filename0\n");
                        }else{
                                last;
                        }
                }
        }
        unlink $handshake_file;
        print("delete $handshake_file\n");
}

writeLog("/tmp/eow.log"," handshake.pl---> end\n");
