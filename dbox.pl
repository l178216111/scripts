#!/usr/local/bin/perl
# CVS ID: $Id: dbox.pl,v 1.44 2006/08/28 18:48:12 rwsk70 Exp $
# Copyright Freescale Semiconductor, Inc. 1998, 2006
#
#################   DBOX FILE TRANSFER PROGRAM   #################
#
#
# Usage:
#
#	dbox.pl [-vsptd1ce] [options] <JobFile> 
#
#   where,
#	-vstd1ce is any combination of the following program options:
#		v - Verbose mode,
#		s - Silent mode (no output to STDOUT, only log file),
#		p - Preserve the input file - no delete, no move,
#		1 - Transfer only one file, then quit.  (For testing.)
#		t - Test mode (Does not alter source file, leaves temp files),
#		d - Produce a listing of the source and target directories, then quit. No transfer.
#		c - Continuous mode,
#		e - Produce source error directory report. (No file transfer.)
#
# Name-Value Options:
#
#	-restore <dirname>	Move files from the named source error 
#				subdirectory up to the main source directory.
#				If all files are moved then the directory is
#				also deleted.  Perform no file transfers.
#				
#
# Command line options may be used to override any default or
# environment settings:
#	-logp <path>	Log file directory (path),
#	-logf <file>	Log file name (no path),
#	-cfgp <path>	Configuration file directory,
#	-tmp  <path>	Temporary working directory,
#	-lib  <path>	Dbox module library directory,
#	-home <path>	The dbox home directory.  (!!!Necessary?)
#
#	<JobFile> is the configuration file specification (no path).
#		If <JobFile> is not specified a default value of 'dbox.job' is used.
#
# Environmental Variables:
#   Dbox will use the following environmental variables, if they are set and not
#   overridden by command line options:
#	DBOX_LIB - Location of Net module and others,
#	DBOX_ROOT - Root directory for dbox versions,
#	DBOX_TMP - Temporary data file processing area,
#	DBOX_LOG - Log file directory,
#	DBOX_CFG - Data flow config. file directory.
#   DBOX_MAILSERVER - Domain address of the mail server to use for error mail.
#

use strict 'vars';    			#Must be first to force strict in all others.

BEGIN {
   my $_DBOX_LIB;		#Path to dbox library.
    # Modify @INC here if necessary
    if ( $ENV{'DBOX_LIB'} ) {	#If DBOX_LIB is set in ENV...
       $_DBOX_LIB = $ENV{'DBOX_LIB'};  #then add it to the search path.
       } else {			#If DBOX_LIB is not set in ENV...
       $_DBOX_LIB = './lib';	#then use the default directory.
       }
    $_DBOX_LIB =~ s/\\/\//g;		#Change any back slashes to forward.
    unshift ( @INC, $_DBOX_LIB );	#Add the dbox library to the search list.
    my $DBOX_UTILS = "$_DBOX_LIB/dbox_utils"; #Place for standard dbox modification modules.
    $DBOX_UTILS =~ s/\\/\//g;		#Change any back slashes to forward.
    unshift ( @INC, $DBOX_UTILS );	#Add the dbox utility dir. to the search list.
}

use File::Copy;						#!!!Might be able to delete this soon.
use File::Path;
use File::stat;
use Cwd;			#Directory management functions- getcwd().
use Net::FTP;
use dbox_lib::FtpClasses;	#Dbox FTP classes.
use dbox_lib::Classes;		#Misc. Dbox classes.
use Cfg;				#Motorola config. file class.
use ClassLogg;			#Motorola log file manager class.
use ClassDbug;			#Motorola debug utility class.
use Sys::Hostname;	#For getting the hostname for logs and emails.

#use Switch;			#CPAN switch module takes too long to load.

#The CPAN modules below could be used to check disk utilization, but their installation
#requires changes in the system PERL library -- a requirement I'm not willing to accept.
#use Filesys::Df;		#Unix Filesystem usage check. Ian Guthrie (CPAN)
#use Filesys::Statvfs;		#Supports Unix Df.  (CPAN)
#use Win32::DriveInfo;		#Windows drive info. (CPAN)
#use Win32::API;

################################################################################
# DEFINE GLOBAL CONSTANTS

use constant TRUE 	=> 1;	     
use constant FALSE 	=> 0;
use dbox_lib::Constants;			#Include global Dbox constants (in dbox_lib).

my $GOOD = Constants::GOOD;			#!!!Constant won't work in a regexp.
my $DBOXDIR = Constants::DBOXDIR;

################################################################################
# DEFINE GLOBAL VARIABLES

my $rhProgParams;			#Hash of options from the Cmd line.
#my $oSrcCtn	= undef;	#Object representing the connection to the source system.
				#!!!Clean up usage of $oSrcCtn. Had to switch it from local to global
				#due to Net:FTP "feature"  and not all subroutines have been
				#converted.
my $DboxHomePath = undef;	#Root dir for various dbox stuff.
my $vLogFileSpec = undef;	#Log file path and name.
my $TmpFilePath = undef;	#Temporary file area.
my $CfgFilePath = undef;	#Config file area.
my $JobCfgFileName = undef;	#Name of job configuration file.
my $LockFileSpec = undef;  	#Lock file spec.  Set in _Initialize().
my $StopJobFile = undef;	#Stop file spec. for the job. Set in _Initialize().
my $StopGlobalFile = 'dbox.stop';	#Global stop file name. Add path in _Initialize().

my $KeepLock = FALSE;		#Decide whether to keep the lock file when aborting.

my @aSourceNotify;		#Array of SourceNotify messages.
my @aAbortNotify;		#Array of AbortNotify messages.
my %haTargetNotify;		#Hash of arrays of TargetNotify messages. Key is TargetSection.
				#Get the username from the environment. (Choose the first non-null variable.)
my $username = $ENV{'LOGNAME'} || $ENV{'USER'} || $ENV{'USERNAME'}; # SH || KSH || Windows
my $DefaultMailServer = 'az33exm20.am.freescale.net';	#Default mail server.
my $MailServer = $ENV{'DBOX_MAILSERVER'} || $DefaultMailServer; #Get the mail server address.
my $DboxHost = hostname();	#Get the hostname for email and logging.
my $OneDone = FALSE;		#Initialize the single-file option.

#----- Performance Statistics ------
my $FileCount = 0;		#Number of files transferred successfully.
my $FailCount = 0;		#Number of failing files moved aside.
my $FailTargetFilterCount = 0;	#Number of files that qualified for no targets.
my $SizeAccum = 0;		#Accumulated size of files transferred (bytes).
my $ElapsedTime = 0;		#Elapsed time to transfer all files.

#############################################################################
# MAIN PROGRAM
#############################################################################

$SIG{__DIE__} = \&HandleDie;	#Set pointer to die, croak signal handler (for timeout).

				#Initialize variables, read command line.
($DboxHomePath,$TmpFilePath,$CfgFilePath,$JobCfgFileName,
 $LockFileSpec,$StopJobFile,$StopGlobalFile,$rhProgParams) = 
   _Initialize();

#=======Derived Global Variables ==============

#==============================================

my %hCfg;							#Top level hash of all parameters from config files.
									#Read the job config file and other configs.
ReadAllCfgFiles($CfgFilePath,$JobCfgFileName,\%hCfg); 

CheckStopFile();					#Check for presence of a stop file.
CheckLockFile($LockFileSpec);		#Check for presence of lock file.
 
									#Create connections to source and targets.
CreateConnections(\%hCfg);	

CheckLocalDirs(\%hCfg);				#Check the local directories in the job file.

#-------- Special Execution Modes ------------

if ( $rhProgParams->{directory} == 1 ) {#If the directory flag is set...
   ShowDirs(\%hCfg);				#Show directory listings.
   goto(NormalExit);				#Jump to the end.
   }
if ( $rhProgParams->{restore} ) {	#If there is a source restore dir set...
									#Move source error files back up.
   RestoreSrcErrFiles(\%hCfg,$rhProgParams->{restore});	
   goto(NormalExit);				#Jump to the end.
   }
if ( $rhProgParams->{error_report} == 1 ) {#If the error report flag is set...
   ErrorReport(\%hCfg);				#Show source error directory listings.
   goto(NormalExit);				#Jump to the end.
   }

#----------- Normal Execution ----------------

AutoRestore(\%hCfg);			#Restore files from designated error dirs for retry.
								#If SourceCache mode is on...
if (%hCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {
	my $oSourceCache = SourceCacheClass->new();
	$oSourceCache->init(\%hCfg,$rhProgParams);	#Initialize the source cache.
}

my $LoopDelay = Constants::DEFAULTLOOPDELAY;	#Set the delay between continuous-mode loops.
if ( %hCfg->{'JobCfgObj'}->getValue('LoopDelay')) { #Use the default or config file.
	$LoopDelay = %hCfg->{'JobCfgObj'}->getValue('LoopDelay');
   }
				
do {				#Loop for continuous mode. Once for batch.
					#Process/transfer all the source dir files.
   ($FileCount,$FailCount,$FailTargetFilterCount,$SizeAccum) = 
      ProcessFilesAndDirs(\%hCfg,$TmpFilePath);

   ClassLogg->Message("File set complete.  $FileCount files transferred. ". 
      "$FailCount files failed. $FailTargetFilterCount failed all filters. ". 
      "$SizeAccum total input bytes");

# In continuous mode there is no email notification except
# during an abort.  We need to have a scheme to send intermediate
# notifications.
#   if ( NotifyTime() ) {	#If it's time to send erro emails...
#      Notify();			#Send any accumulate error email.
#      }

   if ( $rhProgParams->{continuous} ) {	#If continuous mode...
      CheckStopFile();		#Abort if requested by a stop file.
      AutoRestore(\%hCfg);#Restore files from designated error dirs for retry.
      ClassLogg->Message("Pausing $LoopDelay seconds.");
      sleep $LoopDelay;		#Pause for loop delay.
      }
   } until ( $rhProgParams->{continuous} != 1 ); #Infinite loop or single shot.

Notify();				#Send last batch of warning emails.
					#Log a summary of the execution.
ClassLogg->Comment("Execution complete.  $FileCount files transferred. $FailCount files failed. $FailTargetFilterCount failed all filters. $SizeAccum total input bytes");

NormalExit:{1;};

if (%hCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {	#If SourceCache mode on...
	%hCfg->{oSourceCache}->Close();	#Close the new file and swap names.
}
unlink($LockFileSpec);			#Remove the lock file.
exit(0);				#End program, normal exit code.


################################################################################
# SUBROUTINES
################################################################################


sub ProcessFilesAndDirs($rhCfg,$TmpFilePath) {

# This subroutine processes all the files in the source directory:
#    - Capture the listing,
#    - Make list of subdirectories,
#    - Move misnamed and oversized files,
#    - Copy each source file to a local temporary area,
#    - Modify the file as necessary,
#    - Copy the modified file to the targets,
#    - Delete the original and temporary files,
#    - Return an array of summary result information.

my $rhCfg 	= shift();	#Reference to the top configuration hash.
my $TmpFilePath = shift();	#Temporary local file area.

my $SourceDir =    $rhCfg->{oSrcDboxCtn}->getValue('CurrentDir');
my $AccessMethod = $rhCfg->{oSrcDboxCtn}->getAccessMethod();

my $OneDone = FALSE;		#Initialize the single-file option.
my $DelCount;				#Counter for number of files deleted by unlink.

#Check each required parameters for validity.
if ( length($AccessMethod) == 0 ) { #If the parameter length is zero...
      _Abort("ERROR: Parameter AccessMethod is missing.");
      }
if ( length($SourceDir) == 0 ) { #If the parameter length is zero...
      _Abort("ERROR: Parameter SourceDir is missing.");
      }
   					#Check throttle and disks before proceeding.
CheckThrottle($rhCfg) or _Abort("Ending due to throttle limit");
CheckDisks($rhCfg,$TmpFilePath) or _Abort("Ending due to disk capacity limit");

ClassLogg->Message("****Processing Files****");
					#Process the files (and subdirectories if in tree mode).
ProcessCurrentDir($rhCfg);

					#!!!Track and print elapsed time.
					#Return counts and size totals for logging.
return($FileCount,$FailCount,$FailTargetFilterCount,$SizeAccum);
}  #sub ProcessFilesAndDirs

#************************************************************
sub ProcessCurrentDir($rhCfg) {
# This subroutine processes all the files in the current
# source directory.  Then, in tree mode, it recursively calls itself to
# process the subdirectories of the current source directory.

my $rhCfg = shift;			#Get reference to the config hash.

my $Result = undef;			#Result string of operations. (Failure mode.)
							#Get the current source directory path.
my $CurrentSrcDir = $rhCfg->{oSrcDboxCtn}->getValue('CurrentDir');
							#Get list of source files and directories.
my ($rahFileListing,$rahDirListing) = $rhCfg->{oSrcDboxCtn}->ls();

foreach my $rhFileEntry ( @$rahFileListing ) {	#For each file listing entry (a hash)...
   
   if ( ($rhProgParams->{onefile} == TRUE) and $OneDone ) { #If the single file flag is set...
      return;				#Exit the for loop -- you're done.
      } else {
      $OneDone = TRUE;
      }
   my $Filename = $rhFileEntry->{name};
   ClassLogg->Message("#####Source file: $Filename");

   $Result = TestFile($rhCfg,$rhFileEntry);  #Decide if it's good for transfer.
   									# $Result contains the failure description.
   if ( $Result eq 'SKIP' ) {		#If TestFile() says to SKIP this file...
      ClassLogg->Message("TestFile() says to SKIP file $Filename.");
      if (%hCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {
         $rhCfg->{oSourceCache}->		#Update the SourceCache with the previous value.
            AddToNewList($rhCfg->{oSrcDboxCtn}->getValue('CurrentDir'),
            $Filename,$rhCfg->{oSourceCache}->{LastTestStatus});
      }
      next;							#Skip to the next input file. No action on this file.
   }					
   if ( $Result ne $GOOD ) {		#If the file is NOT good for transfer...
   					#move file to a source sub directory.
      if ( (!$rhProgParams->{'test'})and(!$rhProgParams->{'preserve'}) ) { #If not test/preserve mode...
         MoveAside($rhCfg,$rahDirListing,$Filename,$Result);	
	  } else {
	     ClassLogg->Message("Test/preserve mode flag prevents move of $Filename to error directory.");
	  }
									#If SourceCache is on, update the output list.
      if (%hCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {
   	     $rhCfg->{oSourceCache}->
            AddToNewList($rhCfg->{oSrcDboxCtn}->getValue('CurrentDir'),
            $Filename,$Result);  
      }   #if SourceCache on.   
      $FailCount++;					#Count number of failed files.
      next;							#Skip to the next file entry.
   }
									#Perform modification.  Copy the file to target(s). 
   ($Result,my $ModFilename,my $rhSuccessTargetList)=
      CopyModifyFile($rhCfg,$TmpFilePath,$Filename);	
   
   									#Update the source cache with the transfer result.
   if (%hCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {
      $rhCfg->{oSourceCache}->AddToNewList($CurrentSrcDir,$Filename,$Result);
   }
   if ( $Result =~ /SKIP/ ) {		#If the modification routine says to SKIP this file...
      ClassLogg->Warning("Mod. module says to SKIP file $Filename.");
					#Delete the original temporary file (unless testing).
      DeleteFile("$TmpFilePath/$Filename");
					#Delete the possible modified temp file (unless testing.
      DeleteFile("$TmpFilePath/$ModFilename");
      next;				#...and skip to the next input file.
   }
   
					#If the file failed to copy/modify...
   if ( ($Result ne $GOOD) )	{
   					#Move original file to a source subdirectory.
      ClassLogg->Error("The result of processing for $Filename was $Result");
      					#Add to email notification.
      push @aSourceNotify, ("The result of processing for $Filename was $Result\n"); 
      					#If not test/preserve mode...
      if ( !( $rhProgParams->{'test'} or $rhProgParams->{'preserve'})) { 
     					#Create an error subdirectory and move file into it.
         MoveAside($rhCfg,$rahDirListing,$Filename,$Result);	
	 } else {
 	 ClassLogg->Message("Test/Preserve mode flag prevents move of $Filename to error directory.");
	 }
      if ( !( $rhProgParams->{'test'} )) {	#If not test mode...
         DeleteFile("$TmpFilePath/$Filename"); 	#Delete temporary input copy.
         DeleteFile("$TmpFilePath/$ModFilename");#Delete possible temporary stub.
         }
      $FailCount++;			#Count number of failed files.
      next;				#Skip to the next file entry.
      }
				#Delete source and tmp files (if not testing or preserving).
   if ( !$rhProgParams->{'test'} ) {
      DeleteFiles($rhCfg,$TmpFilePath,$Filename,$ModFilename);
      }
   					#If all went well but no targets qualified...
   if (($Result eq $GOOD) and (! keys(%$rhSuccessTargetList))) { #and NoTargetOkay isn't set...
      $FailTargetFilterCount++;		#Accumulate the number of no-target files.
      $SizeAccum += $rhFileEntry->{size}; #Accumulate file byte count.
      ClassLogg->Comment(join(' ',$Filename,'qualified for no targets',
         'Size=',$rhFileEntry->{size}));
      next;
      }						#Make a suitable log entry.
   LogTransferSuccess($Filename,$rhSuccessTargetList,$rhFileEntry->{size});

   $FileCount++;			#Accumulate number of successful files.
   $SizeAccum += $rhFileEntry->{size};	#Accumulate file byte count.
   
   					#Check throttle, disks, and stop file before proceeding.
   if ( ! ($FileCount % Constants::CHECKFREQ) ) {  #For efficiency, only check every nth time.
      CheckThrottle($rhCfg) or _Abort("Ending due to throttle limit");
      CheckDisks($rhCfg,$TmpFilePath) or 
         _Abort("Ending due to disk capacity limit");
      CheckStopFile();		#Abort if a stop file is present.
      }   

   }   #foreach $rhFileEntry
							#All the files in the current dir have been transferred.

#-------- Handle Tree Modes -----------
							#Read the tree mode from the job file (or undef).
my $TreeMode = $rhCfg->{JobCfgObj}->getValue('TreeMode');
if ($TreeMode) {			#If we need to traverse the source tree...
							#For each eligible source subdir...
   foreach my $rhSrcSubDir (@$rahDirListing) {
   	
      my $DirName = $rhSrcSubDir->{name}; #Get the dir name from the listing hash.
      							#If this directory doesn't qualify for processing...
      if ( ! QualifyDir($DirName,$rhCfg)) { 
         ClassLogg->Message("Skipping source directory $DirName");
         next;					#Skip processing this directory.
      }
      ClassLogg->Message("Processing source directory $DirName");
      							#"cd" into the source subdirectory.
      $rhCfg->{oSrcDboxCtn}->chCurrentDir($DirName);
       
      if ($TreeMode eq 'TreeToTree') {	#If we're in Tree-to-Tree mode...
         						#Move the targets down a directory level.
         CdTargets($$rhCfg{TrgObjHash},$DirName,$rhCfg);
      }   #if TreeToTree
      
      							#Recursively process directories.
      ProcessCurrentDir($rhCfg);
      
      							#"cd" the source directory back up 1 level.
      $rhCfg->{oSrcDboxCtn}->chCurrentDir('..');
      if ($TreeMode eq 'TreeToTree') {	#If we're in Tree-to-Tree mode...
         						#Move the targets back up a directory level.
         CdTargets($$rhCfg{TrgObjHash},'..');
      }   #if TreeToTree
        
   }   #foreach hSubDir.
}   #if $TreeMode.

}   #ProcessCurrentDir()

#***********************************************
sub CdTargets($rhTrgObjHash,$DirName) {
# This subroutine moves the current directory for each target down
# into the specified directory.  The directory is created if necessary.
# There is no actual OS cd command.  We only change the CurrentDir attribute.

my $rhTrgObjHash = shift;			#Get ref. to the hash of target connection objects.
my $DirName = shift;				#Get the name of the new dubdirectory.

foreach my $TargetSection ( sort keys %$rhTrgObjHash ) {  #For each target section...

   my $oTrgCtn = $rhTrgObjHash->{$TargetSection};	#Point to the current target object.

   if ((! $oTrgCtn->dirExists($DirName)) and	#If the new directory doesn't exist...
       ( $DirName !~ /^\./ )) {		#and the new dir is not '.' or '..' then
      $oTrgCtn->mkDir($DirName);		#Create the directory on the target.
   }
   $oTrgCtn->chCurrentDir($DirName);	#Move the target into the directory.
}   #foreach TargetSection
}   # CdTargets()

#*******************************************************************
sub QualifyDir($DirName, $rhCfg) {
# This subroutine compares the current directory name to 
# the match strings in the job file (DirNameSpec and DirNameIgnore) and to the
# fixed Dbox regular expression to determine if the directory
# should be processed in tree mode or skipped.
# Directories created by Dbox operations (e.g. error directories)
# do not qualify for processing.

my $DirName = shift;
my $rhCfg = shift;
							#Get the job specified match strings.
my $DirNameSpec = $rhCfg->{JobCfgObj}->getValue('DirNameSpec');
my $DirNameIgnore = $rhCfg->{JobCfgObj}->getValue('DirNameIgnore');

if (((length($DirNameSpec)  ==0) or ($DirName =~ /$DirNameSpec/)) and
    ((length($DirNameIgnore)==0) or ($DirName !~ /$DirNameIgnore/)) and
    ($DirName !~ /$DBOXDIR/)) {
   return(TRUE)				#Directory qualifies for processing.
   } else {
   return(FALSE)};			#Directory should not be processed.
}   #QualifyDir()

#*******************************************************************

sub CopyModifyFile($rhCfg,$TmpFilePath,$Filename) {

# This subroutine copies the specified source file to the target(s)
# and performs the modification specified in the configuration file.
# !!!Implement a performance saving shortcut to MOVE the file when
# the source and targets are local.
# This routines returns a Result string containing a success indicator or
# the failure description.

my $rhCfg = shift();			#Top config hash.
my $TmpFilePath = shift();		#Isn't it obvious?
my $Filename = shift();			#Filename to transfer.

my $Result;						#Success indicator.
my %SuccessTargetList;			#List of successful targets w/ filenames(for logging).

					#Copy the file to the local temp area.
($Result,$Filename) = $rhCfg->{oSrcDboxCtn}->CopyToTemp($rhCfg,$TmpFilePath,$Filename);
if ( $Result ne $GOOD ) { goto(ExitSubroutine) };

					#Modify the file per the Modify list in config file.
($Result,my $ModOutFilename,my $ModTargetList) = Modify($TmpFilePath,$Filename,$rhCfg);
if ( $Result !~ /^$GOOD/ ) { goto(ExitSubroutine) };

					#Copy the file to the targets.
($Result) = CopyToTargets($rhCfg,$TmpFilePath,
					$ModOutFilename,$ModTargetList,\%SuccessTargetList);
if ( $Result ne $GOOD ) { goto(ExitSubroutine) };

ExitSubroutine:{1;};
return($Result,$ModOutFilename,\%SuccessTargetList); #Return $ModFilename so it can be deleted.

}   #sub CopyModifyFile

#*************************************************
sub Modify($TmpFilePath,$InFilename,$rhCfg) {
#
#This subroutine loads the file modification modules specified in the
#config file and executes the subroutines inside.
#If there is no modification specified then these statements should fall
#through, with the only action being to initialize $ModFilename.
#
#The modification routine should return a result code string as follows:
#	GOOD -	Modification was successful.
#	GOOD0 -	Successful, and only target number 0 qualifies for delivery.
#	GOOD0,2 - Successful, and only targets 0 and 2 qualify for delivery.
#	GOOD_id1[,id2,...]
#		 - Successful, and only targets with a matching TargetModQualify value
#		   should receive the file.
#	SKIP - 	The input file should be left untouched. Proceed to the next file.
#	All other values indicate a failure and the nature of the failure.

my $TmpFilePath = shift();				#Get the path to the temporary area.
my $InFilename = shift();				#Get the incoming filename.
my $rhCfg = shift();					#Get pointer to config hash.

my $ModOutFilename = $InFilename;		#Initialize the final filename in case there is no mod.
my $ModInFilename  = $InFilename;		#and initialize input filename for possible first module.
   					# $ModOutFilename must always contain a valid name.					#Get the Modify module name from config file.
my $ModModuleList = $rhCfg->{'JobCfgObj'}->getValue('Modify');  #Get list of modification modules.
my $Result=$GOOD;				#Initialize success indicator (in case of no modules).
my $ModTargetList=undef;		#Optional CSV string of qualified targets from 
								#the modification routine.

foreach my $ModModule ( split(/\s+/,$ModModuleList) ) {   #For each modification module...
   ClassLogg->Message("Calling module $ModModule for file $ModInFilename");
   eval {							#Wrap the user module to catch errors.
      require "$ModModule.pm";		#Load the modification module.
      								#Perform the modification by calling the module.
									#Use same name for file, package, and subroutine.
      ($Result,$ModOutFilename) = $main::{$ModModule."::"}->{$ModModule}->($TmpFilePath,$ModInFilename); #Execute the mod subroutine.

      ClassLogg->Message("Result from module $ModModule is $Result");

      if ( $Result =~ /^ABORT/ ) {	#If the module says to abort...
         _Abort("Mod. module $ModModule return status was $Result");
      }

      if ( $Result !~ /^$GOOD/ ) {	#Test for success.  If mod failed...
         $Result = "Modify_$Result";#Prepend the user description with our own.
         if ( ! $ModOutFilename ) {   	#If the failing module returns an empty ModOutFilename...
            ClassLogg->Message("ModOutFilename was empty from $ModModule. Using $ModInFilename");
            $ModOutFilename = $ModInFilename; #Capture the orphaned filename for later deletion.
         }
	 				#Delete the tmp files (unless we're in test mode).
	 if ( -e "$TmpFilePath/$ModInFilename" and !$rhProgParams->{'test'} ){
            unlink("$TmpFilePath/$ModInFilename") or	#Delete interim files as we're through with them.
               ClassLogg->Error("Could not delete temporary file $TmpFilePath/$ModInFilename");
            }
	 if ( -e "$TmpFilePath/$ModOutFilename" and !$rhProgParams->{'test'} ){
            unlink("$TmpFilePath/$ModOutFilename") or	#Delete interim files as we're through with them.
               ClassLogg->Error("Could not delete temporary file $TmpFilePath/$ModOutFilename");
            }
         goto(ExitSubroutine);
	 }
      };   #end eval
      
   if ($@) {				#If there is an error message from eval...
      _Abort("Eval of module $ModModule for file $ModInFilename failed:",$@);  #Log the error string.
      }    
   					#Check for an optional INTEGER target list from the mod module.
   if ( $Result =~ /^($GOOD)([0-9].*)/ )  { #If the modification module specified a target...
      $ModTargetList = $2;		#Get CSV list of qualifying targets.
      ClassLogg->Message("Modify target list: $ModTargetList");
      }					#Note that only the last target list is retained.
      
   					#Check for an optional STRING target list from the mod module.
   if ( $Result =~ /^($GOOD)_(.*)/ )  { #If the modification module specified a target...
      $ModTargetList = $2;		#Get CSV list of qualifying targets.
      ClassLogg->Message("Modify target list: $ModTargetList");
      }					#Note that only the last target list is retained.

      
   if ( $ModInFilename ne $ModOutFilename ) {   #If the in/out files are different...
      ClassLogg->Message("Deleting possible temp file $ModInFilename");
      unlink("$TmpFilePath/$ModInFilename") or	#Delete interim files as we're through with them.
         ClassLogg->Message("Could not delete possible temporary premod. file $ModInFilename");
      $ModInFilename = $ModOutFilename;	#Update input filename for next module.
      }
   }  #foreach ModModule
   
ExitSubroutine:{1;};					#Jump here for anything but "GOOD*"
return($Result,$ModOutFilename,$ModTargetList);
}   #Modify()

#*************************************************
sub LogTransferSuccess($SourceFilename,$rhSuccessTargetList,$Size) {

# This subroutines builds the log message for a successful transfer.
# The message may take one of four formats, depending on whether
# the filename was changed. (Example shows two targets):
#
#	<Filename> transferred to <Target1> <Target2>, Size=<Size>
#	<Filename> transferred to <Target1> <Target2> as <NewFilename>, Size=<Size>
#	<Filename> transferred to <Target1> as <Filename1>, <Target2> as <Filename2>, Size=<Size>
#	<Filename> transferred to NO_TARGETS, Size=<Size>
#
# Note that the logging module will prepend a timestamp to the beginning
# of the line.
# Note that the order of printing of the targets may not be the
# same order as delivery because we are storing the targets in a hash.

my $SourceFilename = shift();			#Source filename.
my $rhSuccessTargetList = shift();		#Reference to list of targets and filenames.
my $Size = shift();						#The size of the source file. (bytes)

my $LogLine = join(' ',$SourceFilename,'transferred to'); #Initialize the log line.

if ( ! keys(%$rhSuccessTargetList)) {	#If the target list is empty...
   $LogLine = join(' ','NO_TARGETS,','Size=',$Size);	#Finish the line and we're done.
   goto(ExitSubroutine);
   }
my @aKeys = sort keys(%$rhSuccessTargetList);	#Make an array of keys so we can look ahead.
my $Count = @aKeys;							#Get length of array.
my $PrintedAs = FALSE;						#Initialize flag for proper formatting.

for (my $i=0; $i<$Count; $i++) { 
	my $Target = $aKeys[$i];			#Get the current target name.
	$LogLine = $LogLine . ' ' . $Target;	#Add the current target to the log line.
	my $Filename = $rhSuccessTargetList->{$Target}; #Get the filename for this target.
	my $FilenameNext = $rhSuccessTargetList->{$aKeys[$i+1]}; #Get the next filename.
							#If we need to print the filename now...
	if ( (($i != $#aKeys) and ($Filename ne $FilenameNext)) or
	     (($i == $#aKeys) and ($Filename ne $SourceFilename)) or
	     ( $PrintedAs )
       ) {
      $LogLine = $LogLine.' as '.$Filename.',';	#Add the filename to the log line.
      $PrintedAs = TRUE;
      }    					#Otherwise, if the names are the same we'll go on to
      						#the next target name and not list the outgoing name yet.
   }   #for each Target i
$LogLine = join(' ',$LogLine,'Size=',$Size); #Add the size to the end of the line.
ExitSubroutine:{1;};
ClassLogg->File($LogLine);				#Make the log entry.
}   #sub LogTransferSuccess

#**************************************************************

sub CopyToTargets
	($rhCfg,$TmpFilePath,$Filename,$ModTargetList,$rhSuccessTargetList) {

# This subroutine copies a file from the local temp directory to 
# the target directories or connections.

my $rhCfg = shift();			#Top config hash.
my $TmpFilePath = shift();		#Isn't it obvious?
my $Filename = shift();			#Filename to transfer.
my $ModTargetList = shift();		#Optional list of qualified targets from Mod.
my $rhSuccessTargetList = shift();  #Hash of successful targets w/ filenames.

my $Result = $GOOD;				#Initialize subroutine return status/error description.
my $RetStatus;					#Command return status.
my $FileQualified=FALSE;		#Initialize target filter qualification flag.

my $rTrgObjHash = $rhCfg->{'TrgObjHash'};#Get a reference to the hash of target objects.
										#For each target section...
foreach my $TargetSection ( sort keys %$rTrgObjHash ) {
								#Set pointer to current target object.
   my $oTrgObj = $rhCfg->{'TrgObjHash'}{$TargetSection}; 
   my $TargetModQualify = $oTrgObj->getValue('TargetModQualify');
   					#Get the module for renaming the file on the way to the 
   					#target (optional).
   my $RenameModule = $oTrgObj->getValue('Rename');

   my $OutFilename = $Filename;	#Initialize target filename (allows for optional rename).
   
   #------Check ModTargetList -----
   #This section determines if the file qualifies for the target based on
   #an approved target list returned by the modification routine.
   #If there is such a list of approved targets it will look like  "0,1,3" or "FAB1, SITE2"
   #in $ModTargetList.  If there is a TargetModQualify value specified in the
   #config file then that integer or string must be found in ModTargetList to qualify.
   #If the config file doesn't specify an integer then this section has no effect.
   #Note that we must test the strings below using length() because they may have
   #a value of zero, which is equivalent to null and undef in PERL.
   
   if ( length($TargetModQualify) > 0 ) {	#If this target has a Mod module qualification 
   						#value specified in the config file...
      if ( length($ModTargetList) == 0 ) {	#Make sure one of the mod modules returned a list.
         ClassLogg->Message("Config target needs a ModTargetList but none specified.");
	 next;					#If nothing to compare then go to next target.
	 }
	 	#If the number or string required by the config file is not found in the list returned
		#from the mod module then this target is disqualified.
      if ( index($ModTargetList,$TargetModQualify) < 0) {
         ClassLogg->Message
	    ("Target $TargetSection did not qualify. Needed \'$TargetModQualify\' in list \'$ModTargetList\'");
         next;				#If none of the mod targets qualified, skip to next target.
	 } else {
         ClassLogg->Message
	    ("Target $TargetSection qualified. Needed \'$TargetModQualify\' in list \'$ModTargetList\'");
	 }
      }					#If a mod target did qualify, proceed to next section.

					#Check filter (and inverse filter) 
					#If the target filter rejects this file...  
   if ( ! TargetFilterApproves($rhCfg,$TargetSection,$TmpFilePath,$Filename) ) {
   	   next;			#...skip to the next target.
   }

   $FileQualified = TRUE;		#The file qualified for at least one target attempt.

   if ( length($RenameModule) != 0 ) {	#If there is a Rename module specified...
					#Create a new name for the outgoing file.
      $OutFilename = RenameInTransit($RenameModule,$Filename); 
      }
									#Do the FTP put or local copy to the target.
   $Result = $oTrgObj->copyToTarget($TmpFilePath,$Filename,$OutFilename);
   
   if ($Result ne $GOOD) {		#If the put failed...
      goto(ExitSubroutine);		#Jump out, return error code.
   }      
					#Add this successful target and filename to the list (for logging).
   $rhSuccessTargetList->{$TargetSection} = $OutFilename;
}   #foreach $TargetSection
					#If file was not copied to any targets because all
					#target filters failed then error.
if ( (! $FileQualified )and($rhCfg->{'JobCfgObj'}->getValue('NoTargetOkay') !~ /y/i)) {
   ClassLogg->Error("No target filters qualified delivery of file $Filename");
   push @aAbortNotify, ("No targets qualified delivery of file $Filename\n"); #Add to email notification.
   $Result= 'NoTargetQualified';
}

ExitSubroutine:{1;};
return($Result);	#Note: This subroutine also returns an updated hash in $rhSuccessTargetList.
}   #sub CopyToTargets.


#******************************************
sub RenameInTransit($RenameModule,$InFilename) {
	
	#This optional subroutine creates a new name for the 
	#data file as it is copied to, or from, the execution system.
	#The rename is accomplished as part of the copy (or FTP get/put)
	#command, optionally as the file is brought into the local
	#system of execution and/or as it is sent to the target.
	#For incoming files, only the new name is used for 
	#processing on the local system of execution.
	#The targets also get the new created during the "get"
	#operation, unless another Rename operation is specified
	#for the target.
	#
	#The primary purpose of this feature is to 
	#facilitate transfer of Unix files whose names
	#may be illegal on a Windows system.  In those cases,
	#the incoming file must have special characters replaced 
	#with a hex encoding.  The outgoing file may need to have
	#the name decoded back to the original.

my $RenameModule = shift();		#Get the rename module name (without .pm).
my $InFilename   = shift();		#Get the input filename.

my $Result;						#Return status from the module.
my $OutFilename;				#The return filename from the module.

ClassLogg->Message("Calling rename module $RenameModule for file $InFilename");
eval {				#Wrap the user module to catch errors.
   require "$RenameModule.pm";		#Load the rename module.
					#Use same name for file, package, and subroutine. Execute the module.
   ($Result,$OutFilename) = $main::{$RenameModule."::"}->{$RenameModule}->($InFilename); 
      
   ClassLogg->Message("Result from module $RenameModule is $Result. New name = $OutFilename");
     
   if ( $Result !~ /^$GOOD/ ) {	#Test for success.  If rename failed...
      _Abort("Return status for module $RenameModule for file $InFilename was $Result");  #Log the error string.
      $Result = "Rename_$Result";	#Prepend the user description with our own.
	   }
   };   #end eval
      
if ($@) {				#If there is an error message from eval...
   _Abort("Eval of module $RenameModule for file $InFilename failed:",$@);  #Log the error string.
   }    
return($OutFilename);
}  #sub  RenameInTransit

#*************************************************************
sub TargetFilterApproves($rhCfg,$TargetSection,$TmpFilePath,$Filename) {
	
# This subroutine checks the target filter (if any) for approval to
# deliver the file to the target.  Return is TRUE if the file is approved
# for the target or if there is no filter specified in the config file.
# Otherwise, the return is FALSE.
# This routine tests both the positive and inverse logic filter options.

my $rhCfg = shift();			#Get reference to the config hash.
my $TargetSection = shift();	#Get the name of the target section.
my $TmpFilePath = shift();		#Obvious again?
my $Filename = shift();			#Get the filename.

my $FilterModule = $rhCfg->{'JobCfgObj'}->getValue('TargetFilter',$TargetSection);  #Get target filter name.
my $Result = TRUE;				#Initialize the result.

if ( $FilterModule ) {			#If there is a filter...
   unshift ( @INC, $CfgFilePath );	#Add the dbox config dir to the search list.
   
   ClassLogg->Message("Calling module $FilterModule for file $Filename");
   eval {				#Wrap the user module to catch errors.
      require "$FilterModule.pm";	#Load the filter module.
									#Execute the filter subroutine.
      my $RetStatus = $main::{$FilterModule."::"}->{$FilterModule}->($TmpFilePath,$Filename); 

      ClassLogg->Message("Result from filter $FilterModule is $RetStatus");
      if ( ! $RetStatus ) { 		#If the file does not qualify for delivery to this target...
         ClassLogg->Message("File $Filename rejected by filter $FilterModule. RetStatus=$RetStatus");
         $Result = FALSE;			#This file is rejected by the target. 
         }
      };   #end eval
      
   if ($@) {				#If there is an error message from eval...
     _Abort("Eval of module $FilterModule for file $Filename failed:",$@); 
     }    
   }  #if $FilterModule
   
   #------Check Inverse filter-----
   my $FilterModuleInv = $rhCfg->{'JobCfgObj'}->getValue('TargetFilterInverse',$TargetSection);  #Get target filter name.

   if ( $FilterModuleInv ) {		#If there is a filter...
      unshift ( @INC, $CfgFilePath );	#Add the dbox config dir to the search list.
   
      ClassLogg->Message("Calling module $FilterModuleInv with inverse logic for file $Filename");
      eval {				#Wrap the user module to catch errors.
         require "$FilterModuleInv.pm";	#Load the filter module.
         my $RetStatus = $main::{$FilterModuleInv."::"}->{$FilterModuleInv}->($TmpFilePath,$Filename); #Execute the filter subroutine.
         $RetStatus = ($RetStatus eq TRUE) ? 0 : 1;	#Reverse the logic.
         if ( ! $RetStatus ) { 		#If the file does not qualify for delivery to this target...
            ClassLogg->Message("File $Filename rejected by inverse logic on filter $FilterModuleInv. RetStatus=$RetStatus");
         $Result = FALSE;			#This file is rejected by the target. 
	    }
         };   #end eval
      
      if ($@) {				#If there is an error message from eval...
        _Abort("Eval of module $FilterModule for file $Filename failed:",$@); 
        }    
      }  #if $FilterModuleInv

return($Result);			#Return TRUE or FALSE.
}   #sub TargetFilterApproves()

#**************************************************************

sub ShowDirs($rhCfg) {

# This subroutine prints directory listings of the source and target directories
# to STDOUT for administrative purposes.  Listings are not sent to the
# log file.  No data files are transferred.  The listings contain ALL files,
# including those that maybe be excluded by a transfer filter.

my $rhCfg = shift();		#Reference to top config hash.
#my $oSrcCtn = shift();		#Source connection object.
#my $rhTrgCtns = shift();	#Hash of target connections.

my $AccessMethod = $rhCfg->{'oSrcDboxCtn'}->getValue('AccessMethod');
my $SrcDir = $rhCfg->{'oSrcDboxCtn'}->getValue('CurrentDir');

#---------- Source Listing ------------------
				#Get list of source files and directories.
my ($rahFileListing,$rahDirListing) = $rhCfg->{oSrcDboxCtn}->ls();

print("\n============= SOURCE FILES ===============\n");
PrintEntries($rahFileListing);

print("\n============= SOURCE DIRECTORIES ===============\n");
PrintEntries($rahDirListing);

#---------- Target Listings ------------------

my @aTargetList = $rhCfg->{'JobCfgObj'}->getList('TargetList');
my $RetStatus;				#Command return status.

my $rTrgObjHash = $rhCfg->{'TrgObjHash'};#Get a reference to the hash of target objects.
										#For each target section of job config file...
foreach my $TargetSection ( sort keys %$rTrgObjHash ) {
   my $TrgDboxCtn = $rhCfg->{'TrgObjHash'}{$TargetSection}; #Handy ref. to connection obj.
   my $TrgAccessMethod = $TrgDboxCtn->getAccessMethod();
   my $TargetDir = $TrgDboxCtn->getValue('CurrentDir');
   my $oTrgCtn = $TrgDboxCtn->getValue('oFtpCtn');	#Get the target connection (for ftp).

   if (($TrgAccessMethod eq Constants::EXTFTPFLAG)||
       ($TrgAccessMethod eq Constants::INTFTPFLAG)) {   
      my $OSType = $TrgDboxCtn->getValue('OSType');
      ($rahFileListing,$rahDirListing) = GetFtpListing($TrgDboxCtn,$OSType);  #Get ftp listing.
      }				#Wish I had a case statement here.

   if ( $TrgAccessMethod eq Constants::LOCALFLAG ) {
      ($rahFileListing,$rahDirListing) = GetLocalDirList($TargetDir);#Get local listing.
      }				#Wish I had a case statement here.

   print("\n============= TARGET FILES - $TargetSection ===============\n");
   PrintEntries($rahFileListing);

   print("\n============= TARGET DIRECTORIES - $TargetSection ===============\n");
   PrintEntries($rahDirListing);
 
   }   #foreach $TargetSection

}   #sub ShowDirs

#**************************************************************

sub ErrorReport($rhCfg) {

# This subroutine prints directory listings of the source error directories
# to STDOUT for administrative purposes.  Listings are not sent to the
# log file.  No data files are transferred.  

my $rhCfg = shift();		#Reference to top config hash.

my $oSrcDboxCtn = $rhCfg->{'oSrcDboxCtn'};	#Handy ref. for source connection object.
my $AccessMethod = $oSrcDboxCtn->getValue('AccessMethod');
my $SrcDir = $oSrcDboxCtn->getValue('CurrentDir');
my $OSType = $oSrcDboxCtn->getValue('OSType');

my $rahSubFileListing;my $rahSubDirListing; #Declare pointers.

print("\n################# DBOX ERROR FILE REPORT #################\n\n");

				#Get list of source files and directories.
my ($rahFileListing,$rahDirListing) = $rhCfg->{oSrcDboxCtn}->ls();

foreach my $Entry ( @$rahDirListing ) {  #For each subdirectory...
   my $SubDir = $Entry->{'name'};		#Get subdirectory name.
   
   print("\n================ $SubDir ================\n");
      									#cd into the error dir on the remote system.
   $oSrcDboxCtn->chCurrentDir( $SubDir );				#and get dir listing.
      									
   PrintEntries($oSrcDboxCtn->getValue('rahFileListing'));	#Print error file listing.
   my $Count = @$oSrcDboxCtn->getValue('rahDirListing');	#Get count of sub-subdirectories.
   if ( $Count > 0 ) {	#If there are sub-subdirectories...
      print("\n==============\nWARNING: There are $Count sub-subdirectories.\n");
      PrintEntries($oSrcDboxCtn->getValue('rahDirListing'));	#Print sub-subdir entries.
      }
   $oSrcDboxCtn->chCurrentDir( '..' );			#Return to source dir.
   }   #foreach $SubDir
}   #sub ErrorReport

#*****************************************************
 
 sub PrintEntries($rahListing) {
 
 # This subroutine prints the entries in the directory listing hash
 # to STDOUT.  Called by ShowDirs().  It also prints some statistics.
 
 my $rahListing = shift();		#Ref to the listing in an array of hashes.
 
 my $CumSize = 0;				#Initialize cumulative size counter.
 my $Count = @$rahListing;		#Get number of entries.
 
 foreach my $rhEntry ( @$rahListing ) {	#For each directory listing entry (a hash)...
   my $Name = $rhEntry->{name};		#!!!Nice to print more file attributes when implemented.
   my $Size = $rhEntry->{size};	
   print("$Name\t$Size\n");			#Print the file listing.
   $CumSize += $Size;			#Accumulate the total byte count.
   }

print("Total $Count entries, $CumSize bytes\n");

}   #sub PrintEntries.

#*******************************************************

sub TestFile($rhCfg,$rhDirEntry) {

# This subroutine tests the specified file's attributes against
# transfer requirements and returns a string.  If the file 
# qualifies for transfer the returned string is 'GOOD'.  If the
# file does not qualify then the returned string contains an 
# error code, which is also the subdirectory name into which 
# the file should be placed.
# !!!Need to add more file tests: permissions, name match.

my $rhCfg 	= shift();	#Reference to the top configuration hash.
my $rhDirEntry 	= shift();	#Get the directory information (hash).

my $TestResult = $GOOD;		#Initialize the result.
my $Filename = $rhDirEntry->{'name'};	#Get filename we're testing.

#-------- Test File Size --------

my $MaxSize = $rhCfg->{'JobCfgObj'}->getValue('MaxSize');  #Get the max allowed file size.
my $FileSize = $rhDirEntry->{'size'}; #Get the size of this file.

if (( $MaxSize > 0) and ( $FileSize > $MaxSize )) {	#If the file is oversized...
   ClassLogg->Error("File $Filename size $FileSize exceeds limit $MaxSize.");
   push @aSourceNotify, ("File $Filename size $FileSize exceeds limit $MaxSize.\n"); #Add to email notification.   
   $TestResult = 'Oversized';		#Update the result.
   goto(ExitSubroutine);
   }
if (($FileSize == 0) and 			#If the file is zero length...
    ($rhCfg->{'JobCfgObj'}->getValue('ZeroOkay') !~ /y/i)) {
   ClassLogg->Error("File $Filename is zero length");
   push @aSourceNotify, ("File $Filename is zero length\n"); #Add to email notification.   
   $TestResult = 'Zero';			#Update the result.
   goto(ExitSubroutine);
   }

#-------- Test File Name ----------
# The test for special characters has been removed because some flows
# do need to use special characters.  Therefore, any special character tests 
# have been moved to modules.
#
# Note that dbox will not transfer filenames containing a space or tab because
# those characters confuse the FTP line parser subroutine.  Those files will be
# ignored completely.

					#Check the filename for illegal characters.
#if ($Filename =~ m/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F-\xFF]/) {
#      ClassLogg->Warning("File name $Filename contains nonprintable characters");
#      $TestResult = 'FilenameNonprint';	#...then flag, move to error dir.
#      goto(ExitSubroutine);
#      }
      					#!!!The pattern below will not catch backquotes.
#if ($Filename =~ m/[!\$\*(){}|\\\;"'<>?,\/\s]/) {
#if ( 0 ){ #$Filename =~ m//) {
#      ClassLogg->Warning("File name $Filename contains special characters");
#      $TestResult = 'FilenameSpecial';	#...then flag, move to error dir.
#      goto(ExitSubroutine);
#      }

if ( IgnoreFile($rhCfg,$Filename) ) {	#If Filename matches FileNameIgnore, skip.
   $TestResult = 'SKIP';		#Result was false. File should not be transferred.
   goto(ExitSubroutine);
   }
				#Check the filename for a match to the config requirements.
				#Get the filename pattern matching string from the config file.
my $MatchExp = $rhCfg->{'JobCfgObj'}->getValue('FileNameSpec');

if ((length($MatchExp) > 0) and 	#If the match expression is not empty and...
    ($Filename !~ m/$MatchExp/ )) {  #If the filename doesn't match the expression...
   ClassLogg->Error("File name $Filename doesn't match $MatchExp.");
   push @aSourceNotify, ("File name $Filename  doesn't match $MatchExp.\n"); #Add to email notification.   
   $TestResult = 'NameMismatch';	#...then flag, move to error dir.
   goto(ExitSubroutine);
   }


#------- Test file against SourceCache --------

if ($rhCfg->{JobCfgObj}->getValue('SourceCache') =~ /y/i) {	#If SourceCache is on...
   if (! $rhCfg->{oSourceCache}->TestFile($rhCfg,$Filename)) {
      $TestResult = 'SKIP';		#Result was false. File should not be transferred.
      goto(ExitSubroutine);
   }
}
ExitSubroutine:{1;};			#Jump here when finished testing.

return($TestResult);			#Return GOOD, SKIP or the error description.
}  #sub TestFile

#*****************************************************

sub IgnoreFile($rhCfg,$Filename) {

# This subroutine tests the input filename for matching the FileNameIgnore
# option in the config file.  If returns TRUE if there is a match
# or FALSE if there is no match or if the FileNameIgnore option
# is not included in the config file.

my $rhCfg 	= shift();	#Reference to the top configuration hash.
my $Filename 	= shift();	#Get the current input filename.

my $MatchExp = $rhCfg->{'JobCfgObj'}->getValue('FileNameIgnore');  #Get the expression from the config file.

if ( length($MatchExp) == 0 ) {		#If there is no expression specified...
   return(FALSE);			#then we're done.
   }
   
if ( $Filename =~ m/$MatchExp/ ) {  #If the filename matches the expression...
   ClassLogg->Message("File $Filename matches FileNameIgnore $MatchExp    Skipping.");
   return(TRUE);			#We have a match.
   } else
   { return(FALSE);			#No match.
   }
   
}   # sub IgnoreFile

#**********************************************************

sub AutoRestore($rhCfg) {

# This subroutine restores files in designated error directories at
# the start of each dbox execution.  Some error directories are specified
# in this program and additional directories may be set in the job file.

my $rhCfg 	= shift();	#Reference to the top configuration hash.

				#Get user specified retry list.
my $UserList = $rhCfg->{JobCfgObj}->getValue('AutoRetryDirs');
				#Final list is hard-coded list plus user dirs.
my $RestoreDirList = join(' ',Constants::AUTORESTOREDIRS,$UserList);
$rhCfg->{'RestoreDirList'} = $RestoreDirList; #Add list to hash for later ref.
my $ExistingDirs;
				#Get list of existing source subdirs.
my ($rahFileListing,$rahDirListing) = $rhCfg->{oSrcDboxCtn}->ls();
				#Build list of existing error dirs so we don't
				#try to restore dirs that don't exist.
foreach my $rhDirLine (@$rahDirListing) {   #Foreach subdirectory listing line/name...
   if ( $rhDirLine->{name} =~ /^\./ ) {		#Skip dirs '.' and '..'
      next;}			#Build string list of dirs.
   $ExistingDirs = join(' ',$ExistingDirs,$rhDirLine->{name});
   }

foreach my $RestoreDir ( split(/\s+/,$RestoreDirList)) {
   if ( $ExistingDirs =~ /$RestoreDir/ ) {  #If our dir is in the list...
      RestoreSrcErrFiles($rhCfg,$RestoreDir);
      }
   }
}   #sub AutoRestore

#****************************************************
sub CheckThrottle($rhCfg) {

# This subroutine checks the throttle directories listed in the 
# configuration file for file counts exceeding the limit in
# the configuration file.  There is no filtering for the
# count -- all files qualify.  Throttle directories
# control flow to all targets and must be on the local system.  
# Their existence was confirmed during program initialization.

my $rhCfg	= shift();		#Reference to the top config hash.

my $rahFileListing; my $rahDirListing;	#Ref. for the current throttle listing.
my $Result = TRUE;			#Initialize return value.

					#Get list of throttle directories.
my $ThrottleList = $rhCfg->{'JobCfgObj'}->getValue('ThrottleList');
					#Get max allowed file count.
my $ThrottleLimit = $rhCfg->{'JobCfgObj'}->getValue('ThrottleLimit');
					#For each throttle directory...
foreach my $ThrottleDir ( (split(/\s+/,$ThrottleList)) ) {
   ClassLogg->Message("Checking throttle directory $ThrottleDir, limit $ThrottleLimit");
					#Get local listing. 
   ($rahFileListing,$rahDirListing) = GetLocalDirList("$ThrottleDir");

   my $FileCount = (@$rahFileListing);	#Get number of files.
   
   if ( $FileCount > $ThrottleLimit ) {
      ClassLogg->Warning("Throttle directory $ThrottleDir file count of $FileCount exceeds limit $ThrottleLimit");
      push @aAbortNotify, ("Throttle directory $ThrottleDir file count of $FileCount exceeds limit $ThrottleLimit\n"); #Add to email notification.   
      $Result = FALSE;			#Set the failure flag. Continue checking dirs.
      }
   }

return($Result);
}   #sub CheckThrottle

#**************************************************************

sub RestoreSrcErrFiles($rhCfg,$SubDir) {

# This subroutine restores files from source error directories by
# moving them back up a level into the source directory.
# We assume that FTP connections are already cd'ed to the desire
# directory (i.e. the source directory).

my $rhCfg = shift();					#Reference to top config hash.
my $SubDir = shift();					#Name of the subdirectory to restore.

my $oSrcDboxCtn	= $rhCfg->{'oSrcDboxCtn'};
my $CurrentDir 	= $oSrcDboxCtn->getValue('CurrentDir');

ClassLogg->Message("RestoreSrcErrFiles: Moving up files in $SubDir");

$oSrcDboxCtn->chCurrentDir($SubDir);	#cd to subdir and get listing.
 										#Get a list of files to move.
my $rahFileListing = $oSrcDboxCtn->getValue('rahFileListing');
my $Count = @$rahFileListing;
$oSrcDboxCtn->chCurrentDir('..');		#cd back up to previous dir.
ClassLogg->Comment("RestoreSrcErrFiles: Restoring $Count files from $SubDir to $CurrentDir");
foreach my $rhDirLine ( @$rahFileListing ) {  #For each file in the current subdir...
   my $Filename = $rhDirLine->{name};

   $oSrcDboxCtn->moveFile($Filename,"$SubDir",'.'); #Move the file up.
   }

					#Now delete the empty error directory.
ClassLogg->Message("RestoreSrcErrFiles: Deleting empty error directory $SubDir");
$oSrcDboxCtn->deleteDir("$SubDir") 	
   or _Abort("RestoreSrcErrFiles: Could not delete $CurrentDir/$SubDir");

}   #sub RestoreSrcErrFiles.

#******************************************************
sub GetLocalDirList($Dir) {

# This subroutine gets a listing of the specified local directory
# and also the file attritutes and returns them in a stat-like array of
# hashes.  Lists of subdirectories and files (really not-subdirs) are
# returned in separate arrays.
# !!!Add option to use relative directory specs. Hint: Test for "." and
# then getcwd() before processing files.

my $Dir = shift();		#Get the local directory specification.

my @ahFileListing;		#Initialize the output array of hashes.
my @ahDirListing;		#Initialize the output array of hashes.
my %hFileStats = undef;		#Initialize hash for a single file.

opendir(DIR,$Dir) or _Abort("Could not list directory $Dir");	#Open the directory. 
my @aFilenames = readdir(DIR);	#Get a list of filenames.
closedir(DIR);

foreach my $Filename ( @aFilenames ) {	#For each directory entry...

   my $dev; my $ino; my $mode; my $nlink; my $uid; my $gid; my $rdev;
   my $size;my $atime;my $mtime;my $ctime;
   my $blksize;my $blocks;
   
   #!!! Fix stat problem.
   ($dev,$ino,$mode,$nlink,$uid,$gid,
    $rdev,$size,$atime,$mtime,$ctime,
    $blksize,$blocks) = (stat "$Dir/$Filename")[0,1,2,3,4,5,6,7,8,9,10,11,12];
    
    my $rStatAry = stat("$Dir/$Filename");
    $mode=$$rStatAry[2];
    $size=$$rStatAry[7];

#   @hFileStats{'name','dev','ino','mode','nlink','uid',
#   	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
#   	($Filename, {stat($Filename)});
   @hFileStats{'name','dev','ino','mode','nlink','uid',
   	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
   	($Filename,$dev,$ino,$mode,$nlink,$uid,
   	$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);

   if (($Filename eq '.')or($Filename eq '..')) {  #Skip directories . and ..
      next;
      }
				#Sort the line by 'file' or 'directory'.
   if ( -d "$Dir/$Filename" ) {		#If entry is itself a directory...
      push @ahDirListing, {%hFileStats};	#Add the hash to the dir list array.
      } else {
      push @ahFileListing, {%hFileStats};	#Add the hash to the file list array.
      }          
   }   #Foreach Filename.

return(\@ahFileListing,\@ahDirListing);
}   #sub GetLocalDirList.

#******************************************************************
#sub GetFtpListing($oDboxCtn) {    !!!Strange that I can't use a prototype anymore on this line.

sub GetFtpListing {

# This subroutine gets a listing of the current FTP directory and
# stores it in an array of hashes.  There is one output array for
# files and a separate array for directories.
# This routine works for internal and external FTP sites.
# If a directory contains files with spaces in the filenames then those
# lines will likely be excluded from the output because the element
# count from split() will not match expectations.
# !!!Need to improve robustness of directory parsing.  Handle varying element counts.

my $oDboxCtn = shift();		#Dbox connection object.
my $OSType = shift();		#Get the config file hash.

				#Values for ftp operating system types.
use constant  UNIX => 'Unix';	#Value indicating a Unix ftp listing.
use constant  OS2  => 'OS2';	#Value indicating an IBM OS/2 ftp listing.
use constant  Microsoft=>'Microsoft';#Value indicating a Microsoft ftp listing.
use constant  Windows=>'Windows';#Value indicating a Windows server. (Need to confirm.)

my $rFtpObj = $oDboxCtn->getValue('oFtpCtn');	#Get the FTP connection object.
my @ahFileListing;				#Initialize the output array of hashes.
my @ahDirListing;				#Initialize the output array of hashes.
my @DirOut;						#Array to hold ftp dir output.

my $CurrentDir = $oDboxCtn->getValue('CurrentDir');

# IMPORTANT NOTE:
# The FTP library dir command does not work properly when passed values beginning
# with a dot.  Therefore, if CurrentDir begins with . , ./ , or .\ we will 
# remove that prefix.  If there is nothing left in Path after the removal then
# we call the dir method with no argument.

my $Path = $CurrentDir;

$Path =~ s/^(\.\/|\.\\|\.)//;	#Remove certain path prefixes.

if ( $Path ne $CurrentDir ) {	#If there was any modification of the path...
   ClassLogg->Message("Modified path for FTP listing of $CurrentDir is $Path");
}

if (length($Path) == 0) {	#If there are no characters left in $Path...
   @DirOut = $rFtpObj->dir();	#Get listing of current directory.
} else {
   @DirOut = $rFtpObj->dir($Path);#Get listing of desired directory.
}

my %hFileStats;			#Hash of the file statistics in "stat" format.
my %hFtpLine;			#Hash of the file statistics in ftp format.

# Example lines from Microsoft. (CHIPPAC, DALSA)
# 331-(220 klftp Microsoft FTP Service (Version 5.0).)
# 10-15-03  05:31PM                64237 algaemb_Oct15.dat
# 06-18-03  05:02PM       <DIR>          barracuda
#
# Example lines from an IBM OS/2 server (Tempe, TFM)
# 220 prcroos9 IBM TCP/IP for OS/2 - FTP Server ver 17:11:22 on Feb  4 1999 ready.
#                 0           DIR   08-28-02   17:37  Aaron
#            110160      A          10-09-02   16:03  Athena_Soft_Dock.SFX
#                24                 08-26-03   03:23  chkdsk.log
#
# Example lines from Redhat? Linux server running WU-FTP at Tundra.
# 331-(220 uxdmz.tundra.com FTP server (Version wu-2.6.2(1) Tue Sep 30 17:16:35 EDT 2003) ready.)
# drwxr-xr-x   3 14151       4608 Feb  9 19:29 unit_probe
# -rw-r--r--   1 14151       2863 Feb  6 19:27 20040123115135_H92J00DS1_H92J_Z31H92J_E56844.1Y_01.mdlp.gz
# -rw-r--r--   1 14151       2833 Feb  6 19:27 20040123121711_H92J00DS1_H92J_Z31H92J_E56844.1Y_02.mdlp.gz
#
# Example lines from a Sun server (emtrans)  Note there are two date formats.
# 220 emtrans FTP server (SunOS 5.6) ready.
# drwxr-xr-x   7 emtrans  artadmin     512 Feb  6 16:38 dbox4
# -rw-r--r--   1 emtrans  artadmin  149308 May 28  2003 TOWER_Fab1_L74R_FN3S0088_03111148.atdf
#
#
# STATS FTP problem - FTP dir fields run together.
# 331-(220 ftpoutg.stats.com.sg FTP server (Version 1.1.214.4(PHNE_27765) Wed Sep  4 05:59:34 GMT 2002) ready.)
# -rw-rw----   1 motorola   motorolaGRP1695368 Apr 16 01:18 20040415-190814_MOS13_STATS_W06L93S_D74817.99K_1_25_prd01_NA.stdf.gz.crypt
# drwxrwx---   2 motorola   motorolaGRP   4096 Apr 16 09:05 DboxErr_NameMismatch

if ( !$OSType ) {		#If OSType is undefined, default to Unix.
   $OSType = UNIX;
   }
   
if ( $OSType eq UNIX ) {	#Select Unix line parsing.
   foreach my $Entry ( @DirOut ) {   #Parse each line. Populate the array of hashes.
      my @aElements = (split(/\s+/,$Entry));		#Split the dir line into an array for testing.
      my $ElementCount = (split(/\s+/,$Entry));		#Count the number of elements in the dir line.
      
      if ( $ElementCount == 0 ) {next}	#Skip blank lines.
   
      #Check for quirk in FTP line where the group and size fields are butted together.  
      #Look for a group of letters followed by a group of digits.
      #If found, split the compound field.
      
      if (( $ElementCount == 8 )and( $aElements[3] =~ m/([a-zA-z_]*)(\d*)/)) {
         my $Group = $1;		#Extract the group from the kludge.
	 my $Size = $2;			#Extract the size from the kludge.
	 ClassLogg->Message("Found irregular FTP dir line. \$aElements[3]=$aElements[3]  Group=$Group  Size=$Size");
	 
	 splice @aElements,3,-1,$Group,$Size,$aElements[4],$aElements[5],$aElements[6],$aElements[7];
         ClassLogg->Message("Repaired to:  @aElements");
	 $ElementCount++;		#Update ElementCount to reflect repair.
	 }
	 							#Consider lines with links too.
      if ( $ElementCount !~ /9|11/ ) {  #Verify this line is a dir listing line.
         ClassLogg->Message("Found $ElementCount elements in $OSType dir entry \'$Entry\'  Skipping line.");
         next;
         }				#Convert the ftp line to a temporary hash.
      @hFtpLine{"Permissions","Number","User","Group","Size","Month",
      	"Day","TimeYear","Filename"} = @aElements;
   				#Re-store some ftp file attributes in PERL stat format.   
      @hFileStats{'name','dev','ino','mode','nlink','uid',
      	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
      	($hFtpLine{'Filename'},undef,undef,undef,undef,undef,
      	undef,undef,$hFtpLine{'Size'},undef,undef,undef,undef,undef);

      if (($hFtpLine{'Filename'} eq '.')or($hFtpLine{'Filename'} eq '..')) {
         next;				#Skip entries . and ..
	 }
 					#Sort the line by 'file', 'directory', or other.
      if ($hFtpLine{'Permissions'} =~ /^(-|l)/ ) {#If first Permission char is '-' or 'l'...
								#Assume that links are files.  Could be a bad assumption.
         push @ahFileListing, {%hFileStats};	#Add the hash to the file list array.
         } else {

         if ($hFtpLine{'Permissions'} =~ /^d/ ) {	#If first Permission char is 'd'...
            push @ahDirListing, {%hFileStats};	#Add the hash to the dir list array.
            } else {
            _Abort("Unrecognized line in FTP listing: $Entry");
            }
         }       
      }   #foreach $Entry.
   }   #If $OSType...

if ( $OSType eq Windows ) {	#Select Windows line parsing.
   foreach my $Entry ( @DirOut ) {   #Parse each line. Populate the array of hashes.
      my $ElementCount = (split(/\s+/,$Entry));
      if ( $ElementCount == 0 ) {next}	#Skip blank lines.
   
      if ( $ElementCount != 8 ) {  #Verify this line is a dir listing line.
         ClassLogg->Message("Found $ElementCount elements in $OSType dir entry \'$Entry\'  Skipping line.");
         next;
         }				#Convert the ftp line to a temporary hash.
      @hFtpLine{'Permissions','Number','User','Size','Month',
      	'Day','TimeYear','Filename'} = (split(/\s+/,$Entry));
   				#Re-store some ftp file attributes in PERL stat format.   
      @hFileStats{'name','dev','ino','mode','nlink','uid',
      	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
      	($hFtpLine{'Filename'},undef,undef,undef,undef,
      	undef,undef,$hFtpLine{'Size'},undef,undef,undef,undef,undef);

      if (($hFtpLine{'Filename'} eq '.')or($hFtpLine{'Filename'} eq '..')) {
         next;				#Skip entries . and ..
	 }
 					#Sort the line by 'file', 'directory', or other.
      if ($hFtpLine{'Permissions'} =~ /^-/ ) { 	#If first Permission char is '-'...
         push @ahFileListing, {%hFileStats};	#Add the hash to the file list array.
         } else {

         if ($hFtpLine{'Permissions'} =~ /^d/ ) {	#If first Permission char is 'd'...
            push @ahDirListing, {%hFileStats};	#Add the hash to the dir list array.
            } else {
            _Abort("Unrecognized line in FTP listing: $Entry");
            }
         }       
      }   #foreach $Entry.
   }   #If $OSType...

#----------------------

if ( $OSType eq Microsoft ) {		#Select Microsoft FTP Service line parsing.
   foreach my $Entry ( @DirOut ) {   #Parse each line. Populate the array of hashes.
      $Entry =~ s/^\s+//;		#Remove leading spaces to avoid subsequent null array entry.
      my $ElementCount = (split(/\s+/,$Entry));
      if ( $ElementCount == 0 ) {next}	#Skip blank lines.
   
      if ( $ElementCount != 4) {  #Verify this is a listing line.
         ClassLogg->Message("Found $ElementCount elements in $OSType dir entry \'$Entry\'  Skipping line.");
         next;
         }				#Convert the ftp line to a temporary array.
      my @aTemp = (split(/\s+/,$Entry));

      if ( $aTemp[2] eq '<DIR>' ) { 	#If the third element is '<DIR>'...
         my $Size = undef;		#There is no size given for directories.
         my $Name = $aTemp[-1];		#The name is always the last entry in the line.
   				#Re-store some ftp file attributes in PERL stat format.   
         @hFileStats{'name','dev','ino','mode','nlink','uid',
         	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
         	($Name,undef,undef,undef,undef,undef,
         	undef,undef,$Size,undef,undef,undef,undef,undef);
         push @ahDirListing, {%hFileStats};	#Add the hash to the dir list array.
         } else {
         my $Size = $aTemp[2];		#The size is always the third entry in the line.
         my $Name = $aTemp[-1];		#The name is always the last entry in the line.
   				#Re-store some ftp file attributes in PERL stat format.   
         @hFileStats{'name','dev','ino','mode','nlink','uid',
         	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
         	($Name,undef,undef,undef,undef,undef,
         	undef,undef,$Size,undef,undef,undef,undef,undef);
         push @ahFileListing, {%hFileStats};	#Add the hash to the file list array.
         }       
      }   #foreach $Entry.
   }   #If $OSType...   

#----------------------

if ( $OSType eq OS2 ) {		#Select IBM OS/2 line parsing.
   foreach my $Entry ( @DirOut ) {   #Parse each line. Populate the array of hashes.
      $Entry =~ s/^\s+//;		#Remove leading spaces to avoid subsequent null array entry.
      my $ElementCount = (split(/\s+/,$Entry));
      if ( $ElementCount == 0 ) {next}	#Skip blank lines.
   
      if ( ($ElementCount < 4 ) or ($ElementCount > 5)) {  #Verify this is a listing line.
         ClassLogg->Message("Found $ElementCount elements in $OSType dir entry \'$Entry\'  Skipping line.");
foreach my $x (split(/\s+/,$Entry)) {
   print("\'$x\'\n");
   }
         next;
         }				#Convert the ftp line to a temporary array.
      my @aTemp = (split(/\s+/,$Entry));
      my $Size = $aTemp[0];		#The size is always the first entry in the line.
      my $Name = $aTemp[-1];		#The name is always the last entry in the line.
   				#Re-store some ftp file attributes in PERL stat format.   
      @hFileStats{'name','dev','ino','mode','nlink','uid',
      	'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
      	($Name,undef,undef,undef,undef,undef,
      	undef,undef,$Size,undef,undef,undef,undef,undef);
 				#Sort the line by 'file', 'directory', or other.
      if ( $aTemp[1] eq 'DIR' ) { 	#If the second element is 'DIR'...
         push @ahDirListing, {%hFileStats};	#Add the hash to the dir list array.
         } else {
         push @ahFileListing, {%hFileStats};	#Add the hash to the file list array.
         }       
      }   #foreach $Entry.
   }   #If $OSType...   
   
return(\@ahFileListing,\@ahDirListing);
}   #sub GetFtpListing

#**********************************************************

sub CheckStopFile() {

# This subroutine checks for the existence of a "stop file".
# The presence of a stop file is a signal to the Dbox job 
# that it should stop processing files and terminate.
# There are two possible stop files to check for:
#      $DBOX_TMP/<jobname>.stop  and 
#      $DBOX_TMP/dbox.stop
#
# The check for <jobname>.stop is for stopping a particular job.
# The check for dbox.pl is for stopping all Dbox jobs.
# Dbox will not remove these stop files.
								#If a stop file exists...
if ( -f $StopJobFile ) {
    _Abort("Ending due to job stop file present: $StopJobFile")
   }
if ( -f $StopGlobalFile ) {
    _Abort("Ending due to global stop file present: $StopGlobalFile")
   }
return();			#Return if there is no stop file found.
}   #sub CheckStopFile()

#**********************************************************

sub CheckDisks($rhCfg,$TmpFilePath) {

# This subroutine checks all the necessary disk volume usage
# against the specified limit and returns a TRUE or FALSE status.
# All disk volumes related to any local target directories
# and environment directories are checked.
# This routine does not check remote target volumes.
# Only certain operating systems are supported.  Unsupported systems
# perform no checks and always return TRUE.

my $rhCfg = shift();			#Top config hash.
my $TmpFilePath = shift();		#Isn't it obvious?

my $RetStatus = TRUE;			#Initialize subroutine return status.

#-------Check (local) targets --------
my $rTrgObjHash = $rhCfg->{'TrgObjHash'};#Get a reference to the hash of target objects.
										#For each target section of job config file...
foreach my $TargetSection ( sort keys %$rTrgObjHash ) {
   my $TrgDboxCtn = $rhCfg->{'TrgObjHash'}{$TargetSection}; #Handy ref. to connection obj.
   my $TrgAccessMethod = $TrgDboxCtn->getAccessMethod();
   my $TrgSysFileName  = $TrgDboxCtn->getSyscfgFilename();
   my $TargetDir = $TrgDboxCtn->getJobDir();

   if ( $TrgAccessMethod eq Constants::LOCALFLAG ) {
      my $PercentUsage = GetPercentUsage($TargetDir);	#Get the utilization for the target volume.
      ClassLogg->Message("Utilization of $TargetDir is $PercentUsage\%.  Limit=",Constants::DISKLIMIT,'%');
      if ( $PercentUsage > Constants::DISKLIMIT ) {
         ClassLogg->Comment("Utilization of volume for $TargetDir is $PercentUsage\%, limit",Constants::DISKLIMIT);
         $RetStatus = FALSE;
         }      
      }   
   }   #foreach $TargetSection
   
#--------Check local ENV directories ----------
#!!!It would be good to test the log directory too but that is not a global variable.

my $PercentUsage = GetPercentUsage($TmpFilePath);	#Get the utilization for the temporary volume.
ClassLogg->Message("Utilization of $TmpFilePath is $PercentUsage\%.  Limit=",Constants::DISKLIMIT,"%");
if ( $PercentUsage > Constants::DISKLIMIT ) {
   ClassLogg->Comment("Utilization of volume for $TmpFilePath is $PercentUsage\%, limit",Constants::DISKLIMIT,'%');
   $RetStatus = FALSE;
   }      

ExitSubroutine:{1;};
return($RetStatus);			#Return TRUE for success or FALSE for failure.
}   #sub CheckDisks($rhCfg)

#************************************************************

sub GetPercentUsage($Path) {

# This subroutine finds the percentage of disk utilization for
# the volume containing the given path.

my $Path = shift();		#The path that indicates the volume of interest.
my $Percentage=0;		#Return variable -- percentage of disk utilization.

if ( $^O =~ 'solaris' )	{	#If we're running on Solaris (Sun)...
   $Percentage=GetPercentUsageSolaris($Path);
   } else {
   ClassLogg->Message("Disk utilization checking not implemented for OS $^O");
   }

return($Percentage);		#Return the percent utilization (as an integer).
}   #sub GetPercentUsage

#****************************************************
sub GetPercentUsageSolaris($Path) {

# This subroutine executes a Unix df command on the specified $Path and 
# returns the percent utilization as an integer.
# There are CPAN modules to do this but they require augmentations to the PERL
# compiler.

my $Path = shift();		#The path that indicates the volume of interest.

				#Run the df command, capture output.
open(DFOUT,"df -k $Path |") or _Abort("Nonzero return status from open(df -k $Path)");

my $DfLine;			#A line of output from df command.
while(<DFOUT>) {
   $DfLine = $_;		#Parse to the last line of output.
   }
close(DFOUT);

my $PctField;			#Find the percent utilization field in the output line.
foreach my $Field ( split(/\s+/,$DfLine) ) {
   if ( $Field =~ /%/ ) {	#Look for a percent sign in the field.
      $PctField=$Field;		
      last;}
   }
$PctField =~ s/%//;		#Delete the percent sign, leaving only the integer.

return($PctField);
}   #sub GetPercentUsage.

#**********************************************************

sub DeleteFiles($rhCfg,$TmpFilePath,$Filename,$ModFilename) {

# This subroutine deletes a file from the source and temp 
# directories following a successful transfer.

my $rhCfg	= shift();	#Reference to the top config hash.
my $TmpFilePath	= shift();	#Path to the temporary file area.
my $Filename	= shift();	#Name of file to delete.
my $ModFilename	= shift();	#Name of optional modified file to delete.
				#NOTE: $ModFilename may be undef.
				
my $AccessMethod = $rhCfg->{oSrcDboxCtn}->getAccessMethod();
my $SrcDir = $rhCfg->{oSrcDboxCtn}->getValue('CurrentDir');
my $Count;			#Number of local files deleted.

ClassLogg->Message("Deleting file $TmpFilePath/$Filename");

				#Delete the copy in temp dir.
DeleteFile("$TmpFilePath/$Filename");

				#If necessary, delete the modified file.
if ( ($ModFilename) and ($ModFilename ne $Filename) ) {
   DeleteFile("$TmpFilePath/$ModFilename");
   }
if (!$rhProgParams->{'preserve'}) {	#If not in preserve mode...
   ClassLogg->Message("Deleting file $AccessMethod $Filename");
   if ( $AccessMethod eq Constants::LOCALFLAG ) {	#Delete local source file.
      DeleteFile("$SrcDir/$Filename");
      }
   if (($AccessMethod eq Constants::EXTFTPFLAG)||
       ($AccessMethod eq Constants::INTFTPFLAG)) {
      $rhCfg->{oSrcDboxCtn}->getValue(oFtpCtn)->delete($Filename) or 
         _Abort("Could not delete $AccessMethod file $SrcDir/$Filename"); 
      }
   }   #end preserve mode if.
}   #sub DeleteFiles

#******************************************************************

sub DeleteFile($FileSpec) {

# This subroutine deletes the specified file from the local file system,
# unless test mode is enabled.
# On failure, an error is logged but it does not abort.
# We first test for existence, so no error is reported if the file doesn't exist.

my $FileSpec = shift();		#Get the filename and path.

if ( -f "$FileSpec" and !$rhProgParams->{'test'} ){
   if ( ! unlink("$FileSpec") ) {
      ClassLogg->Error("Could not delete file $FileSpec");
      push @aAbortNotify, ("Could not delete file $FileSpec\n"); #Add to email notification.  
      } 
   }
}   #sub DeleteFile

#***********************************************************

sub CheckLocalDirs($rhCfg) {

# This subroutine checks local directories for existence and
# correct permissions (read for sources, write for targets).
# The routine _Aborts on failure.
# If the AccessMethod for a system is not 'Local' then
# there is no test here for the directory.

my $rhCfg = shift();		#The top config hash reference.

my $oJobCfg = $rhCfg->{'JobCfgObj'}; #The job config object.
my $Dir = undef;		#Hold temporary directory name.

#--- Check source directory.
my $oSrcSys = $rhCfg->{oSrcDboxCtn};  #Find the source config object.
my $AccessMethod = $rhCfg->{oSrcDboxCtn}->getAccessMethod();
   
if ($AccessMethod eq Constants::LOCALFLAG) {		#If this is a local directory...
   $Dir = $oJobCfg->getValue('SourceDir');#Get the dir name.
   my $SourceSystem = $oJobCfg->getValue('SourceSystem');
   ClassLogg->Message("Checking directory $Dir on system $SourceSystem");   
   
   if (!(( -d $Dir )&&( -r $Dir ))) {	#If is not dir or not readable...
      _Abort("\"$Dir\" is not a local directory or is not readable");
      }   #if ! -d -r
   }  #if $AccessMethod
   
#--- Check target directories.
my @TargetList = $oJobCfg->getList('TargetList');	#Get list of target names.

foreach my $TargetSection ( @TargetList ) { #For each target section in job config file...
   $AccessMethod = $rhCfg->{'TrgObjHash'}{$TargetSection}->getAccessMethod();

   if ($AccessMethod eq Constants::LOCALFLAG) {		#If this is a local directory...
      $Dir = $oJobCfg->getValue('TargetDir',$TargetSection);	#Get the target dir.
      ClassLogg->Message("Checking directory $Dir on system $TargetSection");   
   
      if (!(( -d $Dir )&&( -w $Dir ))) {	#If is not a dir or not writable...
         _Abort("\"$Dir\" is not a local directory or is not writable");
         }   #if ! -d -w
      }  #if $AccessMethod

#--- Check throttle directories.
   my @ThrottleList = ( split(/\s+/,$oJobCfg->getValue('ThrottleList',$TargetSection)) );
   foreach $Dir ( @ThrottleList ) {		#For each throttle directory...
      ClassLogg->Message("Checking throttle directory $Dir on system $TargetSection");   
   
      if (!(( -d $Dir )&&( -r $Dir ))) {	#If is not a dir or not readable...
         _Abort("\"$Dir\" is not a local directory or is not readable");
         }   #if ! -d -r
      }   #foreach $ThrottleDir
   }  #foreach $TargetSection
}   #sub CheckLocalDirs.

#*********************************************************************

sub ReadAllCfgFiles($CfgFilePath,$JobCfgFileName,$rhCfg) {
# This subroutine reads the job configuration file and the
# system configuration files that are specified in the
# job file.  It returns a job config file object.
# Configuration Data Structure
#
# %hCfg				Top level hash containing all config data.
#    $oJobCfg			Object containing all the parameters from the job file.
#       $MaxSize		Maximum size (bytes) of files to transfer.
#       $FileNameSpec		Spec for required filename substring(s).
#   $oSrcDboxCtn		Connection object for source.
#	$SourceModify		File modification spec. (for all source files).
#   %TrgObjHash			Hash of target objects.
#      $oTrgDboxCtn		An object for each target.


my $CfgFilePath = shift();	#Path to all the config files.
my $JobCfgFileName = shift();	#Job config filename.
my $rhCfg	= shift();	#Get reference to config hash.

my $oSrcDboxCtn = undef;		#Declare the reference for the source object.
								#Read the parameters for the transfer job.
my $oJobCfg = ReadCfgFile($CfgFilePath.'/'.$JobCfgFileName);
								#Read the source syscfg file to find the access method.
my $oSyscfg = ReadCfgFile($CfgFilePath.'/'.$oJobCfg->getValue('SourceSystem'));
								#Find the source access method.
my $AccessMethod = $oSyscfg->getValue('AccessMethod');

								#Create new connection object for the source.
if ($AccessMethod eq Constants::LOCALFLAG) {
   $oSrcDboxCtn = BaseConnection->new();		#Create a local (base) object for the source.
}
if (($AccessMethod eq Constants::INTFTPFLAG) or
    ($AccessMethod eq Constants::EXTFTPFLAG)) {
   $oSrcDboxCtn = DboxFtpConnection->new();	#Create an FTP object for the source.
}
# Set some source attributes.
									#Set the source access method.
$oSrcDboxCtn->setValue('AccessMethod',$AccessMethod);
									#Set a ref. to the syscfg file object.
$oSrcDboxCtn->setValue('oSyscfg',$oSyscfg);
									#Set the source syscfg filename from the job file.
$oSrcDboxCtn->setSyscfgFilename($oJobCfg->getValue('SourceSystem'));
									#Set the source directory from the job file.
$oSrcDboxCtn->setJobDir($oJobCfg->getValue('SourceDir'));
   									#Set the FTP operation timeout value.  (Not idle timeout.)
my $FtpTimeout = $oJobCfg->getValue('FtpTimeout');
if ($FtpTimeout) {					#If there is a special value in the job file...
   $oSrcDboxCtn->setValue('FtpTimeout',$FtpTimeout);	#Use special job value.
} else {							#Otherwise, use the default value.
   $oSrcDboxCtn->setValue('FtpTimeout',Constants::TIMEOUT);
}  
									#Name is the TargetSection for targets; just SOURCE here.
$oSrcDboxCtn->setValue('Name','SOURCE');

									#Load the master configuration hash.
%$rhCfg = (
      'JobCfgObj'	=> $oJobCfg,
      'oSrcDboxCtn'	=> $oSrcDboxCtn
         );

$oSrcDboxCtn->loadSyscfgFile($CfgFilePath);

									#Get the list of targets (config file sections).
my @TargetList = $oJobCfg->getList('TargetList');

my %hTrgObjs;						#Hash of target objects.
foreach my $TargetSection ( @TargetList ) {  #Get all the target info into object.
									#Read the target syscfg filename from the job object.
   my $TrgSysFileName = $oJobCfg->getValue('TargetSystem',$TargetSection);
									#Read the syscfg file for the target.
   my $oSysCfg = ReadCfgFile($CfgFilePath.'/'.
   					$oJobCfg->getValue('TargetSystem',$TargetSection));
   									#Find the AccessMethod for the target.
   my $AccessMethod = $oSysCfg->getValue(AccessMethod);
   my $oTrgDboxCtn = undef;			#Declare new object reference.
									#Create proper type of connection object for the target.
   if ($AccessMethod eq Constants::LOCALFLAG) {
      $oTrgDboxCtn = TargetLocalConnection->new();#Create new object for this target.
   }
   if (($AccessMethod eq Constants::INTFTPFLAG) or
       ($AccessMethod eq Constants::EXTFTPFLAG)) {
      $oTrgDboxCtn = TargetFtpConnection->new();#Create new object for this target.
   }								#Foreach target parameter from list...
   foreach my $Attribute (Constants::TARGETATTRIBUTES) {
							#Copy the value from the job object to the new target object.
      $oTrgDboxCtn->setValue($Attribute,$oJobCfg->getValue($Attribute,$TargetSection));
   }
   					#Set more attributes for the target connection.
   $oTrgDboxCtn->setValue('Name',$TargetSection);
   $oTrgDboxCtn->setValue('AccessMethod',$AccessMethod);
   $oTrgDboxCtn->setValue('SyscfgFilename',$oJobCfg->getValue('TargetSystem',$TargetSection));
									#Attribute TargetDir is not used. Use JobDir instead.
   $oTrgDboxCtn->setValue('JobDir',$oJobCfg->getValue('TargetDir',$TargetSection));
   									#Set the timeout value for FTP operations. (Not idle timeout.)
   my $FtpTimeout = $oJobCfg->getValue('FtpTimeout',$TargetSection);
   if ($FtpTimeout) {				#If there is a special value in the job file...
      $oTrgDboxCtn->setValue('FtpTimeout',$FtpTimeout);	#Use special job value.
   } else {							#Otherwise, use the default value.
   $oTrgDboxCtn->setValue('FtpTimeout',Constants::TIMEOUT);
   }  
   $oTrgDboxCtn->loadSyscfgFile($CfgFilePath);	#Creates oSysCfg attribute.
   
   					#Get the temporary target directory (optional).
   $oTrgDboxCtn->setValue('TempTargetDir',
      SetTmpTrgDir($oJobCfg->getValue('TempTargetDir',$TargetSection)));
   
   					#Add the target system object to the hash of targets.
   $hTrgObjs{"$TargetSection"} = $oTrgDboxCtn;
   
   }   #foreach TargetSection.

$rhCfg->{'TrgObjHash'}={%hTrgObjs};	#Add the hash of targets to the master config hash.
									#Set the preserve flag based on config file.
if (($rhCfg->{'JobCfgObj'}->getValue('PreserveSource') =~ /y/i) or
    ($rhCfg->{'JobCfgObj'}->getValue('SourceCache') =~ /y/i)) {
   $rhProgParams->{preserve} = 1;	#SourceCache mode also requires preserve mode.
   }

}  #sub ReadAllCfgFiles.

#*********************************************************************
sub SetTmpTrgDir ($InTmpTrgDir) {

# This subroutine sets the functional temporary target directory
# based on the string received from the job file.  
# The job file may specify an actual directory, or the special value 'no',
# or the parameter may be missing.
# If the job value is 'no' we return the do-not-use value of '.'.
# If the job value is empty/missing we return the Dbox default value.

my $InTmpTrgDir = shift;			#Get the dir (if any) specified in the job.

my $OutTmpTrgDir = Constants::TMPTARDIR;		#Initialize to default.

if ( length($InTmpTrgDir) > 0 ) {	#If there is a temporary target directory specified...
   if ( $InTmpTrgDir =~ /^no$/i ) {	#If the temp directory is specified 'no'...
      $OutTmpTrgDir = '.';			#Then set to '.' indicating feature not used.
   } else {
   $OutTmpTrgDir = $InTmpTrgDir;	#Use the value specified by the job file.
   }
}   # if length > zero.
return($OutTmpTrgDir);				#Return the TmpTrgDir.
}  #sub SetTmpTrgDir()

#**************************************************************

sub _Initialize() {

#This subroutine initializes most program variable, including handling of
#command line and environment variables.  It does not read any
#configuration files.
#The operating variables (ROOT,LOG,TMP,CFG) are determined according to this precedence:
#	1. Command line specification,
#	2. Environment variable specification,
#	3. Hard-coded default.

my $LogFilePath;			#Path to log file.
my %ProgParams;				#Hash of command line options and other parameters.
$ProgParams{'verbose'} = 1;		#Set default verbosity value (includes warnings).

my $Program;				#The name of this PERL program from Cmd line.
my @OrigARGV = @ARGV;			#Capture original ARGV for logging.
_HandleCmdLine(\%ProgParams);#Process the command line parameters.

					# SET PROGRAM PARAMETERS
					# Note: DBOX_LIB, also required, was tested in BEGIN.
					# Precedence: ProgParam hash, then %ENV, then hard-code.
my $DboxHomePath= $ProgParams{'home'} ||	#Get the home directory.
		  $ENV{'DBOX_ROOT'} ||
		  '.';	
my $LogFilePath	= $ProgParams{'logp'} ||	#Get the log directory.
		  $ENV{'DBOX_LOG'} ||
		  '.';	
my $DBOX_TMP	= $ProgParams{'tmp'} ||		#Get the temporary file area (top level).
		  $ENV{'DBOX_TMP'} ||
		  '.';		
my $CfgFilePath	= $ProgParams{'cfgp'} ||	#Get the config file directory.
		  $ENV{'DBOX_CFG'} ||
		  '.';		
my $JobFilename =        $ProgParams{'cfgfile'} ||	#Set the job config filename.
		  'dbox.job';		#!!! Might want to pretty up the JobFilename handling.

$ProgParams{'DBOX_TMP'} = $DBOX_TMP;	#Add the DBOX_TMP path to the ProgParams hash.
$ProgParams{'JobFilename'} = $JobFilename;	#Add the final job filename to the hash.

if ( ! -r "$CfgFilePath/$JobFilename") {#If the job file doesn't exist...
										#Don't log the error because we don't 
										#want to create a bogus log file.
   printf("FATAL: Job file does not exist or is not readable: $CfgFilePath/$JobFilename");
   exit(1);								#Fatal error exit code.
}

$JobFilename =~ /^(.+)\.(.+)$/;			#Get the prefix of the config file name.
my $JobFilenamePrefix = "$1";
unshift ( @INC, $CfgFilePath );		#Add the dbox config dir to the search list.
   
					#Create the log filespec.
my $LogFileName = "$JobFilenamePrefix.log";	#Set the log file name:  <configprefix>.log
my $LogFileSpec = join ('/',$LogFilePath,$LogFileName);

my $ProgramPrefix = (split(/\./,__FILE__))[0];  #Get the prefix of the program name.
					#Initialize the log file.
#	            Verbosity,            Append,      StdOut,            FileSpec,Autosave, Delete, Trim
ClassLogg->Init($ProgParams{'verbose'}, TRUE, !$ProgParams{'silent'}, $LogFileSpec, 1,    FALSE, Constants::LOGSIZE);

ClassLogg->Program($username,'on',$DboxHost,
   	'starting',__FILE__,@OrigARGV);#Log the program name and all cmd parameters.

ClassLogg->Message(
   "Variables: \$DboxHomePath=$DboxHomePath\t\$LogFileSpec=$LogFileSpec\t\$DBOX_TMP=$DBOX_TMP\t\$CfgFilePath=$CfgFilePath\t\$JobFilename=$JobFilename");

foreach my $Key ( keys(%ProgParams) ) {		#Log all the program parameters.
   ClassLogg->Message('Program Parameter:',$Key,'=',$ProgParams{$Key});
   }

#---------- Lock File -----------
# The lock file prevents duplicate dbox jobs from starting.
# It's too soon to check the lock file and Abort. Just build LockFileSpec now and check later.
$LockFileSpec = "$DBOX_TMP/$JobFilenamePrefix.lock";  #Build lock file spec.

#---------- Stop Files -----------
# The presence of one of these files will top the job.
$StopJobFile = "$DBOX_TMP/$JobFilenamePrefix.stop";  #Build the job stop file spec.
								#$StopGlobalFile was primed with the filename earlier.
								#Now prepend the path.
$StopGlobalFile = $DBOX_TMP . '/' . $StopGlobalFile;

					#Initialize the debugger utility.
#		Filename,   Package, Append, StdOut,  FileSpec,       AutoSave,Delete
#ClassDbug->Init(__FILE__,__PACKAGE__,TRUE,   TRUE,$ProgramPrefix . '.dbg', 1 , TRUE);

					#Check local directories and files.
CheckLocalObj($DboxHomePath,'drw');
CheckLocalObj($LogFilePath,'drw');	#!!!Resolve chicken-egg on checking log dir.
CheckLocalObj($DBOX_TMP,'drw');
CheckLocalObj($CfgFilePath,'drw');
CheckLocalObj("$CfgFilePath/$JobFilename",'r' );
					#Create working dir for the job.
my $TmpJobFilePath = "$DBOX_TMP/$JobFilenamePrefix";
if ( ! -d $TmpJobFilePath ) {		#If the directory doesn't already exist...
   ClassLogg->Comment("Creating working directory $TmpJobFilePath");
   mkdir $TmpJobFilePath  or _Abort("Cannot create  directory $TmpJobFilePath");
   }

return($DboxHomePath,$TmpJobFilePath,$CfgFilePath,$JobFilename,
       $LockFileSpec,$StopJobFile,$StopGlobalFile,\%ProgParams);
}   #End _Initialize

#*****************************************************************

sub _HandleCmdLine($rhProgParams) {

# This subroutine reads the command line parameters into a hash.

my $rhProgParams = shift();		#Get the address of %ProgParams.

while (@ARGV)  {			#For each command line argument...
   my $Arg = shift(@ARGV);		#Get the next argument.
   
   if ( $Arg eq '-restore' ) {
      $rhProgParams->{'restore'} = shift(@ARGV);#Get the source subdir name to restore.
      next; }
   if ( $Arg eq '-logp' ) {
      $rhProgParams->{'logp'} = shift(@ARGV);	#Get the log file path.
      next; }
   if ( $Arg eq '-logf' ) {
      $rhProgParams->{'logf'} = shift(@ARGV);	#Get the log file name (no path).
      next; }
   if ( $Arg eq '-tmp' ) {
      $rhProgParams->{'tmp'} = shift(@ARGV);	#Get the temporary working area.
      next; }
   if ( $Arg eq '-cfgp' ) {
      $rhProgParams->{'cfgp'} = shift(@ARGV);	#Get the config file path.
      next; }
   if ( $Arg eq '-home' ) {
      $rhProgParams->{'home'} = shift(@ARGV);	#Get the dbox home path.
      next; }
   if ( $Arg =~ /^-/ )	{ #If next parameter starts with '-' and didn't match anything above...
      _ReadProgParams($Arg,$rhProgParams);		#Initialize the single-character options.
      next; }
   						#If no matches in the above ifs, then assume...
   $rhProgParams->{cfgfile} = $Arg;		#The config filename.
   }   #while @ARGV      

}   #End _HandleCmdLine

#*************************************************************

sub _ReadProgParams($OptionString,$rhProgParams) {

# This subroutine parses the program options string from the command
# line and sets the values in the %ProgParams hash accordingly.

my $OptionString = shift();		#Get the command line option string.
my $rhProgParams = shift();		#Get the pointer to the options hash.
	
if ( $OptionString =~ /v/ ) {		#Turn on verbose mode.
   $$rhProgParams{'verbose'} = 2;
   }
if ( $OptionString =~ /s/ ) {		#Turn on silent mode.
   $$rhProgParams{'silent'} = 1;
   }
if ( $OptionString =~ /p/ ) {		#Preserve the input file.
   $$rhProgParams{'preserve'} = 1;
   }
if ( $OptionString =~ /t/ ) {		#Turn on test mode.
   $$rhProgParams{'test'} = 1;
   }
if ( $OptionString =~ /c/ ) {		#Set continuous flag..
   $$rhProgParams{'continuous'} = 1;
   }
if ( $OptionString =~ /d/ ) {		#Turn on directory mode.
   $$rhProgParams{'directory'} = 1;
   }
if ( $OptionString =~ /1/ ) {		#Turn on single file mode.
   $$rhProgParams{'onefile'} = 1;
   }
if ( $OptionString =~ /e/ ) {		#Turn on error report mode.
   $$rhProgParams{'error_report'} = 1;
   }
   
my $VerbString;
foreach my $Key ( keys %$rhProgParams ) {#Put all the options on one line.
   $VerbString = "$VerbString\t$Key = $$rhProgParams{$Key}";
   }
ClassLogg->Message("ProgParams: $VerbString");
					#!!!Would rather the above be a case statement.
}   #End _ReadProgParams

#*****************************************************************

sub CreateConnections($rhCfg) {

# This subroutine creates connection objects to the source and
# target systems as necessary.  For any systems that are
# the local system the returned FTP objects are set to undef.
# This routine also cd's the objects to the specified directory 
# in the config file.   
# The routine returns oFtpCtn attributes in the source and target
# Dbox connection objects, and undef for local connections.
# The routine also does an ls on the connections to initialize
# the directory listings.

my $rhCfg = shift();		#Get the config file hash.

$rhCfg->{oSrcDboxCtn}->CreateConnection();#Initialize source connection object.

#----------- Target Systems -----------

my $rTrgObjHash = $rhCfg->{'TrgObjHash'};#Get a reference to the hash of target objects.
										#For each target section of job config file...
foreach my $TargetSection ( sort keys %$rTrgObjHash ) {
   my $TrgDboxCtn = $rhCfg->{'TrgObjHash'}{$TargetSection}; #Handy ref. to connection obj.
									#Initialize the system connection. (Includes FTP login.)
   $TrgDboxCtn->CreateConnection();
   $TrgDboxCtn->checkTargetStopDir();	#Check for the presence of a target stop directory.
}   #foreach $TargetSection

return();
}   #sub CreateConnections.

#*****************************************************************
sub ConnectFtpExternal ($oCfg) {

# This subroutine establishes an ftp connection to an external server, through 
# the gateway, and cd's to the desired directory.  Parameters are taken 
# from the configuration object.
# !!! Implement use of Net::message() or other method to get FTP error messages.

my $oDboxCtnObj   = shift();		#Reference to the Dbox connection object.

				#Get config parameters from config object.
my $SystemName = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('SystemName');
my $AccountSpec = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountSpec');
my $AccountPw = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountPw');

				#Get config parameters from config object.
my $GatewayName = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('GatewayName');
my $GatewayAccount =$oDboxCtnObj->getValue(oSyscfg)->getValue('GatewayAccount');
my $GatewayPassword=$oDboxCtnObj->getValue(oSyscfg)->getValue('GatewayPassword');
my $AccountSpec = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountSpec');
my $AccountPw = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountPw');
my $Timeout =		$oDboxCtnObj->getValue(FtpTimeout);

#Check each required parameters for validity.
my @aRequiredParams = (GatewayName,GatewayAccount,GatewayPassword,AccountSpec,AccountPw);
foreach my $Parameter (@aRequiredParams) {
   if ( length($oDboxCtnObj->getValue(oSyscfg)->getValue($Parameter)) == 0 ) { #If the parameter length is zero...
      _Abort("ERROR: Parameter $Parameter is missing.");
      }
   }

#Set the verbosity of the FTP operations.
#Dbox verbosity is 1 (not verbose) or 2 (verbose), according to ClassLogg requirements.
#Map this into 0 or 1 for Net:FTP requirements.
my $FtpVerbosity = $$rhProgParams{'verbose'} -1;

ClassLogg->Message("Connecting to gateway \"$GatewayName\"");
				#Connect to the gateway.

my $rFtpObj = Net::FTP->new( $GatewayName, Timeout => $Timeout, Debug => $FtpVerbosity ) or
    _Abort("Can not connect to gateway $GatewayName.  $@");

				#Login to the remote system, through the gateway.
$rFtpObj->login( $AccountSpec . ' ' . $GatewayAccount, $AccountPw, $GatewayPassword ) or
    _Abort("Could not log into either $oDboxCtnObj->{Name} using $AccountSpec " .
    		"or gateway $GatewayName using $GatewayAccount.");

$rFtpObj->binary() or
    _Abort("Could not switch to binary ftp mode.");

return($rFtpObj);
}   #sub Connect_ftp_external.

#*****************************************************************
sub ConnectFtpInternal ($oDboxCtnObj) {

# This subroutine establishes an ftp connection to an internal server 
# (no gateway) and cd's to the desired directory.  Parameters are taken 
# from the configuration object.
# !!! Implement use of Net::message() or other method to get FTP error messages.

my $oDboxCtnObj   = shift();		#Reference to the Dbox connection object.

				#Get config parameters from config object.
my $SystemName = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('SystemName');
my $AccountSpec = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountSpec');
my $AccountPw = 	$oDboxCtnObj->getValue(oSyscfg)->getValue('AccountPw');
my $Timeout =		$oDboxCtnObj->getValue(FtpTimeout);

#Check each required parameters for validity.
my @aRequiredParams = (SystemName,AccountSpec,AccountPw);
foreach my $Parameter (@aRequiredParams) {
   if ( length($oDboxCtnObj->getValue(oSyscfg)->getValue($Parameter)) == 0 ) { #If the parameter length is zero...
      _Abort("ERROR: Parameter $Parameter is missing.");
      }
   }

#Set the verbosity of the FTP operations.
#Dbox verbosity is 1 (not verbose) or 2 (verbose), according to ClassLogg requirements.
#Map this into 0 or 1 for Net:FTP requirements.
my $FtpVerbosity = $rhProgParams->{'verbose'} -1;

ClassLogg->Message("Connecting to system \"$SystemName\"");
				#Connect to the gateway.
my $rFtpObj = Net::FTP->new( $SystemName, Timeout => $Timeout, Debug => $FtpVerbosity ) or
    _Abort("Can not connect to system $SystemName.  $@");

				#Login to ftp server.
$rFtpObj->login( $AccountSpec, $AccountPw ) or
    _Abort("Could not log into $oDboxCtnObj->{Name} using $AccountSpec in $SystemName");

				#Switch to binary mode.
$rFtpObj->binary() or
    _Abort("Could not switch to binary ftp mode.");

return($rFtpObj);
}   #sub ConnectFtpInternal.

#****************************************************

sub MoveAside($rhCfg,$rahDirListing,$Filename,$DirSuffix) {

# This subroutine creates an error sub directory on the 
# source system (if not already existing) and moves the
# specified problematic file into it.
# The new directory is a subdirectory of the source 
# directory.  We assume that the source connection
# is already positioned in the source directory.
# The TestResult is the name of the error subdirectory.
# NOTE: It would be nice to use MoveFile() for some of this work
# but currently there are some differences to overcome.  Now with
# the new OO version we need to revisit using moveFile.

my $rhCfg	= shift();	#Reference to the top config hash.
my $rahDirListing=shift();	#Directory listing.
my $Filename	= shift();	#The problematic file name.
my $DirSuffix	= shift();	#Suffix of the error subdirectory name.

my $oSrcDboxCtn = $rhCfg->{oSrcDboxCtn};	#Make handy ref. to source object.
my $AccessMethod= $oSrcDboxCtn->getValue('AccessMethod');
my $SourceDir	= $oSrcDboxCtn->getValue('CurrentDir');
my $DirName	= join('_',Constants::DBOXERRDIR,$DirSuffix);  #Add prefix to make error dir name.
my $SubDirSpec	= "$SourceDir/$DirName";  #Make full path to new dir.

if ( $AccessMethod eq Constants::LOCALFLAG ) {
   if ( ! -d $SubDirSpec ) {		#If the directory doesn't already exist...
      my $SrcSysFilename = $rhCfg->{'JobCfgObj'}->getValue('SourceSystem');
      ClassLogg->Message("Creating error directory $SubDirSpec on system $SrcSysFilename");
      mkdir $SubDirSpec  or _Abort("Cannot create  directory $SubDirSpec");
      }
      					#Move the file to error directory.
   ClassLogg->Warning("Moving file $Filename to directory $SubDirSpec");
   move("$SourceDir/$Filename","$SubDirSpec/$Filename") or   #Move the file to subdir.
      _Abort("Cannot move file $SourceDir/$Filename to $SubDirSpec");
   push @aSourceNotify, ("Moving file $Filename to directory $SubDirSpec\n"); #Add to email notification.
   }
   
if (($AccessMethod eq Constants::EXTFTPFLAG)||
    ($AccessMethod eq Constants::INTFTPFLAG)) {
   my $oFtpCtn = $oSrcDboxCtn->getValue('oFtpCtn');	#Get ref. to the FTP object.
   if ( ! $oSrcDboxCtn->dirExists($DirName) ) {   #If the directory doesn't already exist...
      $oSrcDboxCtn->mkDir($DirName);
      }
   ClassLogg->Warning("Moving file $Filename to directory $DirName");
   if ( ! $oFtpCtn->rename( $Filename, "$DirName/$Filename" )) {	#Move the file to the error dir.
      		#If the move failed, see if it failed because the file already exists.
      $oFtpCtn->cwd( $DirName ) or _Abort("Could not cwd to $DirName");	#cd into the error dir.
      my $OSType = $oSrcDboxCtn->getValue('OSType');
      my ($rahFileListing,$rahErrDirListing) = $oSrcDboxCtn->ls();  #Get ftp listing.
      my $FoundMatch = 0;			#Initialize a flag for matching filenames.
      foreach my $rhDirLine ( @$rahFileListing ) {  #For each file in the error subdir...
         my $ErrFilename = $rhDirLine->{name};	#Get the filename from the listing line.
         if ( $Filename eq $ErrFilename ) {#If the existing error filename matches the file we're moving...
            $FoundMatch = 1;			#Set the found flag.
	    last;
	    }
         }   #foreach
      if ( $FoundMatch ) {		#If an error file already exists...delete it.
         ClassLogg->Warning("Deleting existing error file $Filename in $DirName");
         $oFtpCtn->delete($Filename) or _Abort("Could not delete $AccessMethod file $DirName/$Filename"); 
	 }
      $oFtpCtn->cwd( ".." ) or _Abort("Could not cwd to ..");#Go back out of the error dir.
      $oFtpCtn->rename( $Filename, "$DirName/$Filename" ) or	#Try the move again.
         _Abort("Error moving $Filename to $DirName/$Filename");
      }   # if rename failed.
   push @aSourceNotify, ("Moving file $Filename to directory $DirName\n"); #Add to email notification.
   }    #if ftp access method.

}   #sub MoveAside

#****************************************************

sub Notify()   {

# This subroutine sends email error notifications to addresses specified
# in the job file.  All of the input variables are global.

my $SourceNotify = $hCfg{'JobCfgObj'}->getValue('SourceNotify'); #Get the source notification email list.
my $AbortNotify  = $hCfg{'JobCfgObj'}->getValue('AbortNotify');  #Get the source notification email list.

ProcNotificationSendMail($SourceNotify,\@aSourceNotify,$JobCfgFileName); #Send source-related email.
ProcNotificationSendMail($AbortNotify, \@aAbortNotify, $JobCfgFileName); #Send abort email.

foreach my $TargetSection (sort keys(%haTargetNotify)) {  #For each TargetSection message array...
   my $TargetNotify = $hCfg{'JobCfgObj'}->getValue('TargetNotify',$TargetSection);  #Get target email list.
   ProcNotificationSendMail($TargetNotify, $haTargetNotify{$TargetSection}, $JobCfgFileName);
   }
}    #sub Notify


#**************************************************

sub ProcNotificationSendMail ($AddrList,$raMsgAry,$JobCfgFileName)  {

#Built from sendmail-2.09.  http://www.tneoh.zoneit.com/perl/SendMail

# This subroutine processes a particular notification -- source, abort, or target.
# If the address list is blank or there are no messages to send, then
# no email is generated.

my $AddrList = shift();			#List of email addresses (or empty).
my $raMsgAry = shift();			#Array of messages (or empty).
my $JobCfgFileName = shift();	#Name of the job file.

					#Fixed portions of the email:
my $Part1 = 'The following errors resulted from Dbox execution of job';
my $Part2 = 'The log file may have additional details.';

if ( $AddrList and (@$raMsgAry > 0) ) {	#If there's an email address and messages waiting...
   ClassLogg->Message("Sending email to $AddrList from Dbox\@$DboxHost using $MailServer");
 
   #use SendMail 2.09;					#Bring in the SendMail.pm module.
   use SendMail;						#Bring in the SendMail.pm module.
   
   my @aAddrList = (split(/\s/,$AddrList));	#Convert address list to array for SendMail.

   my $sm = new SendMail($MailServer);	#Create a new mail object.
   #$sm->setDebug($sm->ON);				#Uncomment this line for serious debugging.
										#Set the mail sender address.
   $sm->From("Dbox-$username on $DboxHost  \<$username\@$DboxHost.noreply\>");
   $sm->Subject("Dbox errors from $JobCfgFileName on $DboxHost");
										#Set the recipient list.
   $sm->To(@aAddrList);
										#Assemble the email body.
   $sm->setMailBody("$Part1 $JobCfgFileName\n\n@$raMsgAry\n\n$Part2");
   if ($sm->sendMail() != 0) {		#Send the message.
   					#If failure, print error but don't call _Abort().
      print STDERR $sm->{'error'}."\n";	#Not sure how this works.
      print STDERR 
         "ERROR: Sending email to $AddrList from Dbox\@$DboxHost via $MailServer\n";
      }
   @$raMsgAry = undef;	#Empty the array. Reset for continuous mode.
   }   #if there is email to send.
}   #sub ProcNotificationSendMail

#****************************************************

sub MakeFtpDir ($rFtpObj,$SubDir,$rahDirListing) {

# This subroutine creates a directory on a remote FTP system.
# It assumes that the directory has already been tested for
# existance and does not already exist.

my $rFtpObj = shift();		#Get reference to the FTP connection.
my $SubDir = shift();		#Get the name of the subdirectory.
my $rahDirListing = shift();	#Get the current list of directories.

my %hFileStats;			#Temporary hash to add to dir list.

ClassLogg->Comment("Making directory $SubDir");
$rFtpObj->mkdir($SubDir) or   #Create the subdirectory.
    _Abort("Could not mkdir $SubDir");

				#Add the new directory to the dir list.
@hFileStats{'name','dev','ino','mode','nlink','uid',
   'gid','rdev','size','atime','mtime','ctime','blksize','blocks'} =
   ($SubDir,undef,undef,undef,undef,undef,
   undef,undef,0,undef,undef,undef,undef,undef);

push @$rahDirListing, {%hFileStats};

}   #End sub MakeFtpDir

#***************************************************
sub HandleDie() {
#
# This subroutine handles a "die" or "croak" command so that the lock file is removed.
# The typical cause of death is an FTP timeout.
   _Abort("Program is dying or croaking. @_");
   }

#*****************************************************
# _Abort(@message)

sub _Abort {
    ClassLogg->Fatal(join ( ' ', @_ ) );
    push @aAbortNotify, join(' ','FATAL',@_); #Add message to the email array.
    Notify();				#Send email notices.
    if ( ! $KeepLock ) {		#If we're not aborting because of a preexisting lock file...
       unlink($LockFileSpec);		#Remove the lock file.
       }
    exit(1);				#Fatal error exit code.
}


#***************************************************
# ExitWarning(@message)

sub ExitWarning {
   ClassLogg->Warning(join ( ' ', @_ ) );
    Notify();					#Send email notices.
    unlink($LockFileSpec);			#Remove the lock file.
    exit(2);
}

#****************************************************************

sub ReadCfgFile($CfgFileSpec) {

#This subroutine reads a config file and returns a
#reference to an object containing the configuration parameters.

my $CfgFileSpec = shift();		#Get config filename.

my $oCfg;				#Config object.

if ( -r $CfgFileSpec ) {
   my $RetMsg = Cfg->new($CfgFileSpec, \$oCfg); #Read the config. file into an object.
   } else {
   _Abort("ERROR: Configuration file $CfgFileSpec not found or not readable.");
   }
   
return($oCfg);				#Return a reference to the new object.
}  # End ReadCfgFile


# $singleQuotedText = _Quote($text)

#*******************************************************************

sub _Quote ($){

# This function returns single quotes around the passed string. 
# Used to format log messages.
    return ( "\'" . shift () . "\'" );
}

#*******************************************************************

sub CheckLocalObj($ObjName,$Attributes) {
#
# This subroutine tests file or directory attributes as specified.  
# Any failure aborts the program.
# $Attributes should contain any of the following letters in any order:
#	d - If the target should be a directory,
#	r - If the target should be readable,
#	w - If the target should be writable.
#
my $ObjName = shift;		#Name of the file or object to test.
my $Attributes = shift;		#Attributes, file or directory.

if ( $Attributes =~ /d/ ) {		#If object should be a dir...
   if ( ! -d $ObjName ) {
      _Abort( 'Object',_Quote($ObjName),'does not point to a directory.');
      }
   }

if ( $Attributes =~ /r/ ) {	#If object should be readable...
   if ( ! -r $ObjName ) {
      _Abort( 'File or directory',_Quote($ObjName),'does not exist or is not readable.');
      }
   }

if ( $Attributes =~ /w/ ) {	#If object should be readable...
   if ( ! -w $ObjName ) {
     _Abort( 'File or directory',_Quote($ObjName),'does not exist or is not writable.');
     }
   }
return($ObjName);
}   #End CheckLocalObj

#*************************************************

sub CheckLockFile($LockFileSpec) {

# This subroutine checks for the presence of a lock file for the job
# and aborts if the file is found.  The file should be deleted at the
# end of every dbox execution.  If a file is found it likely means that 
# the previous execution of the job is still in progress.
# The lock file prevents duplicate dbox jobs from starting.

my $LockFileSpec = shift();		#Path and name for lock file for this job.
if ( -f $LockFileSpec ) {		#If the lock file exists...
   $KeepLock = TRUE;			#Set flag to keep lock file.
   _Abort("Lock file exists:  $LockFileSpec");  #Abort now.
   }					#Otherwise, create a new lock file.
open(LOCKFILE,">$LockFileSpec") or _Abort("Could not open lock file $LockFileSpec");
close(LOCKFILE);
 }   #sub CheckLockFile

#*************************************************

__END__

################### OBSOLETE CODE #######################
# The following code is no longer in use and may be deleted.
#**************************************************************

sub Clear($rhCfg,$oSrcCtn,$rhTrgCtns) {

# This subroutine restores source and target file conditions
# in preparation for testing:
#   * Files in error directories are moved back up to the source directory.
#   * All files in the temporary working area are deleted.
#   * All files in the target directories are deleted.
#   * All files in the test data directory are copied to the source.

my $rhCfg = shift();		#Reference to top config hash.
my $oSrcCtn = shift();		#Source connection object.
my $rhTrgCtns = shift();	#Hash of target connections.

my $AccessMethod = $rhCfg->{'SrcSysObj'}->getValue('AccessMethod');
my $SrcDir = $rhCfg->{'JobCfgObj'}->getValue('SourceDir');
my $Count;			#Number of local files deleted.

				#Get list of source files and all subdirectories.
				#The file list is not used here.
my ($rahFileListing,$rahDirListing) = GetSrcDirListing($rhCfg,$oSrcCtn);

foreach my $rhDirLine (@$rahDirListing) {   #Foreach subdirectory listing line/name...
   my $SubDir = $rhDirLine->{name};
   if ( $SubDir =~ /^\./ ) {		#Skip dirs '.' and '..'
      next;
      }
   ClassLogg->Warning("RestoreSrcErrFiles is DISABLED.");
#   RestoreSrcErrFiles($rhCfg,$oSrcCtn,$SubDir);	#Move source error files back up.
   }

$Count = unlink glob("$TmpFilePath/*");		#Delete all files in temp dir.
ClassLogg->Message("Deleted all $Count files in $TmpFilePath");

#---------- Delete files in targets ------------------

my @aTargetList = $rhCfg->{'JobCfgObj'}->getList('TargetList');
my $RetStatus;				#Command return status.

foreach my $TargetSection ( @aTargetList ) {  #For each target section of job config file...
   my $TrgAccessMethod = $rhCfg->{'TrgObjHash'}{$TargetSection}->getValue('AccessMethod');
   my $TargetDir = $rhCfg->{'JobCfgObj'}->getValue('TargetDir',$TargetSection);
   my $oTrgCtn = $rhTrgCtns->{$TargetSection};	#Get the target connection (for ftp).

   ClassLogg->Message("Deleting $TrgAccessMethod files in target directory $TargetDir");
   if ( $TrgAccessMethod eq Constants::LOCALFLAG ) {
				#!!!Relative addressing won't work (on PC).
     $Count = unlink glob("$TargetDir/*");
     ClassLogg->Message("Deleted all $Count files in $TargetDir");
      }
      
   if (($TrgAccessMethod eq Constants::EXTFTPFLAG)||
       ($TrgAccessMethod eq Constants::INTFTPFLAG)) {
#
# Dang!!! I can't seem to find a way to do an ftp mdel * to clear out the target directory.
# The commands below don't work or are not supported.  The work around is to get a listing
# and delete the files one at a time. Later.  Also, don't forget to clean out the temp target
# directories.
#      $RetStatus = $oTrgCtn->mdel('*' );
#      $RetStatus = $oTrgCtn->quot(mdel,'*');
      $RetStatus = TRUE;			#Force true to avoid error branch.
				#!!!Improve error handling here.
      if ( ! $RetStatus ) {
         _Abort("Could not delete all files in $TrgAccessMethod target directory $TargetDir. FTP status = $RetStatus");
         }   		   
      }
   }   #foreach $TargetSection

#------------ Copy test data files to source ------------

ClassLogg->Message("Copying $TestDataDir files to $AccessMethod source directory $SrcDir");
if ( $AccessMethod eq Constants::LOCALFLAG ) {
   my ($rahFileListing,$rahDirListing) = GetLocalDirList("$TestDataDir");#Get local listing.
   
   foreach my $rhDirLine ( @$rahFileListing ) {  #For each file in the current subdir...
      my $Filename = $rhDirLine->{name};
      
      ClassLogg->Message("Copying $Filename from $TestDataDir to $SrcDir");
      copy("$TestDataDir/$Filename","$SrcDir") or _Abort("Could not copy $TestDataDir/$Filename to $SrcDir");
      }
   }
      
if (($AccessMethod eq Constants::EXTFTPFLAG)||
    ($AccessMethod eq Constants::INTFTPFLAG)) {
   $RetStatus = $oSrcCtn->mput( "$TestDataDir/*" );
   
   if ( ! $RetStatus ) {
      _Abort("Could not copy $TestDataDir/* to $SrcDir");
      }
   }
}   #sub Clear.



#####################################################################

Pseudo Code
-----------

Initialize everything.

Read the job config file and the system config files.

Check dirs, mounts, disk space, and everything.

Process source directory
   Get a directory listing.
   Process nonqualifying files (bad name, size)
   Get list of files to transfer.  If there are files...

Delay to hopefully allow files to complete writing.

Attempt to deliver any queued files.

For each file in list...
   Qualify the file (name, size, permissions, etc.).
   If qualification fails, move file to error dir on source. Goto next file.
   Move good file to temp dir on source.
   Receive a copy to temp area (If source is local, just reference. ?)
   Perform source-related processing
   For each target...
      Perform target-related processing.
      Copy file to target.
      Queue file if copy failed.
   If at least one target delivery succeeded...
      Archive the file (optional)
      Delete file from source (or move to "Done" dir).
   Goto next file

Deliver alarms as necessary.
Write summary to log.
Manage log file.
End.
      
