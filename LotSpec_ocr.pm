#  ***************************************************************************
# *
# *   Copyright (c) 2004 by Freescale Semiconductors
# *   Confidential and Proprietary
# *   All Rights Reserved
# *
# *   This software is furnished under license and may be used and copied
# *   only in accordance with the terms of said license and with the
# *   inclusion of the above copyright notice. This software and any other
# *   copies thereof may not be provided or otherwise made available to any
# *   other party. No title to and/or ownership of the software is hereby
# *   transferred.
# *
# *   The information in this software is subject to change without notice
# *   and should not be construed as a commitment by Freescale.
# *
# *
# * @(#)$Id: LotSpec.pm,v 1.7 2005/09/07 07:50:57 probe Exp $
# * Last Revised By   : $Author: probe $
# * Last Checked In   : $Date: 2005/09/07 07:50:57 $
# * Last Version      : $Revision: 1.7 $
# *
# * Origin            : Austin Test Data Systems (8/4/2004 RAD)
# * Notes             : Perl5 Source for LotSpec moduel
# *
# ***************************************************************************

## ------------------------------------------------------------- ##
package LotSpec_ocr;
## ------------------------------------------------------------- ##
##   Perl module to handle validation and parsing 
##   of Lot numbers and Device names. 

require 5.000;
use strict;

my $RCS = '$Id: LotSpec.pm,v 1.7 2005/09/07 07:50:57 probe Exp $';
my $VERSION = (split ' ', $RCS)[2];

my $LotID_spec = q/^(([A-Z]{1,2})([0-9]{5}))\.(([0-9]{1,2})([A-Z]))$/;
my $DevID_spec = q/^([0-9A-Z]+)?([A-Z][0-9]{2}[A-Z])([-0-9A-Z]+)?$/;

my $OCR_FABLOT = $ENV{'OCR_FABLOT'} || '/exec/apps/probe_config/fablot_ext/fablot_ocr.txt';
#my $OCR_FABLOT = $ENV{'OCR_FABLOT'} || '/exec/apps/probe_config/fablot_ext/sue/fablot_ocr.txt';

my %FABID = (
	'ATMC' =>	[ 'D','DD','DE', ],
	'OHTFAB' =>	[ 'E', 'EE', 'ER', 'EW',],
	'TLS' =>        [ 'BE', 'BC', ],
	'CHDFAB' =>	[ 'T', 'TT', 'TP','TH','TM','TN','TR', ],
	'Crolles' =>    [ 'NE','PG', ],
	'Charter' =>    [ 'YK','EK', ],
   );

my %FABScribeChecksum = (
	'ATMC' =>	'SEMI_M12',
	'OHTFAB' =>	'none',
	'TLS' =>        'SEMI_M12',
	'CHDFAB' =>	'none',
        'Crolles' =>    'SEMI_M12',
	'UMC' =>	'SEMI',
	'CSM7' =>    'SEMI_M12',
        'Charter' =>    'none',
	''      =>	'SEMI_M12',	#DEFAULT
   );

my %IDtoFAB;

   my $fab;
   for $fab (keys %FABID) {

	my $id;
	for $id ( @{ $FABID{$fab} } ) {

		$IDtoFAB{$id} = $fab;
   	}
   }

## ------------------------------------------------------------- ##
sub new {
## ------------------------------------------------------------- ##
##  constructor for LotSpec module
##    1 arg  - sets initial value of LotID
##    2 args - sets inital value of DevID, LotID

    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{LotID} = undef;
    $self->{DevID} = undef;

    ($self->{DevID}, $self->{LotID} ) = @_ 	if int(@_) == 2;
     $self->{LotID} = $_[0] 			if int(@_) == 1;

    bless($self, $class);
}

## ------------------------------------------------------------- ##
sub LotID {
## ------------------------------------------------------------- ##
##    get : with no argument, returns the current value of LotID
##    set : with 1 argument, set the current value of LotID

  my $self = shift;

  $self->{LotID} = $_[0] if $_[0];
  return $self->{LotID};
}

## ------------------------------------------------------------- ##
sub DevID {
## ------------------------------------------------------------- ##
##    get : with no argument, returns the current value of DevID
##    set : with 1 argument, set the current value of DevID

  my $self = shift;

  $self->{DevID} = $_[0] if $_[0];
  return $self->{DevID};
}

## ------------------------------------------------------------- ##
sub DevID_mask {
## ------------------------------------------------------------- ##
##    get : returns the last 4 digits of DevID

  my $self = shift;
  return undef unless  $self->{DevID};

  return substr($self->{DevID},4,4) if
    $self->LotID_fab() eq 'TLS';
  return $2 if
    $self->{DevID} =~ /$DevID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_valid {
## ------------------------------------------------------------- ##
##    get : returns true if LotID is valid

  my $self = shift;
  return undef unless  $self->{LotID};

  return $self->{LotID} =~ /$LotID_spec/i;
}

## ------------------------------------------------------------- ##
sub CheckLetter_valid {
## ------------------------------------------------------------- ##
##    get : returns true if Check letter is valid

  my $self = shift;
  return undef unless  $self->{LotID};
  
  return ($self->LotID_checkletter() eq calc_chk_let($self->LotID_number(), $self->LotID_ext_num()));
}

## ------------------------------------------------------------- ##
sub DevID_valid {
## ------------------------------------------------------------- ##
##   get : returns true if DevID is valid

  my $self = shift;
  return undef unless  $self->{DevID};

  return $self->{DevID} =~ /$DevID_spec/i;
}

## ------------------------------------------------------------- ##
sub LotID_fab {
## ------------------------------------------------------------- ##
##    get: returns initial letter(s) of the LotID

  my $self = shift;
  return undef unless  $self->{LotID};

  return undef unless  $self->{LotID} =~ /$LotID_spec/;
  return $IDtoFAB{$2};
}

## ------------------------------------------------------------- ##
sub LotID_fabid {
## ------------------------------------------------------------- ##
##    get: returns initial letter(s) of the LotID

  my $self = shift;
  return undef unless  $self->{LotID};

  return $2 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub FabIDs {
## ------------------------------------------------------------- ##
##    get: returns list of valid prefixes for given fab

  my $self = shift;
  return undef unless  $self->{LotID};

  my $fab = shift;
  return undef unless  defined $FABID{$fab};

  return @{ $FABID{$fab} };
}

## ------------------------------------------------------------- ##
sub LotID_parent {
## ------------------------------------------------------------- ##
##    get: returns all of LotID to the left of the "dot"

  my $self = shift;
  return undef unless  $self->{LotID};

  return $1 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_number {
## ------------------------------------------------------------- ##
##    get: returns just the 'number' part of the lotID

  my $self = shift;
  return undef unless  $self->{LotID};

  return $3 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_ext {
## ------------------------------------------------------------- ##
##    get: returns the part of the lotID after the 'dot'

  my $self = shift;
  return undef unless  $self->{LotID};

  return $4 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_ext_num {
## ------------------------------------------------------------- ##
##    get: returns just the 'number' part of the lotID extension

  my $self = shift;
  return undef unless  $self->{LotID};

  return $5 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_checkletter {
## ------------------------------------------------------------- ##
##    get: returns the last letter in the lotID

  my $self = shift;
  return undef unless  $self->{LotID};

  return $6 if
    $self->{LotID} =~ /$LotID_spec/;
}

## ------------------------------------------------------------- ##
sub LotID_scribe {
## ------------------------------------------------------------- ##
##    get: returns the wafer scribe given a wafer id

  my $self = shift;
  return undef unless  $self->{LotID};

  my $wafid = shift;
  return undef unless $wafid eq 'xx' || ( $wafid >= 1 && $wafid <= 25 );

  my $foundryid = shift;

  return undef unless $self->{LotID}  =~ /$LotID_spec/;
  my $parent = $1;
#add dev to found ocr file ----Liuzx 2016/6/27
#  return calc_scribe($self->{LotID}, $wafid, $foundryid);
  return calc_scribe($self->{LotID}, $wafid, $foundryid,$self->{DevID});

}


## ------------------------------------------------------------- ##
sub bist {
## ------------------------------------------------------------- ##
##   returns a debug string that exercizes all "get" methods

  my $s = shift;
  return undef unless  $s->{LotID} || $s->{DevID};

  return '  $self->{LotID}  '. ($s->LotID || '<null>') ."\n".
         '  $self->{DevID}  '. ($s->DevID || '<null>') ."\n\n".
         '  $self->LotID_valid()       '.($s->LotID_valid       || '<null>')."\n".
         '  $self->DevID_valid()       '.($s->DevID_valid       || '<null>')."\n".
	 '  $self->LotID_fabid()       '.($s->LotID_fabid       || '<null>')."\n".
	 '  $self->LotID_fab()         '.($s->LotID_fab         || '<null>')."\n".
         '  $self->LotID_parent()      '.($s->LotID_parent      || '<null>')."\n".
         '  $self->LotID_number()      '.($s->LotID_number      || '<null>')."\n".
         '  $self->LotID_ext()         '.($s->LotID_ext         || '<null>')."\n".
	 '  $self->LotID_ext_num()     '.($s->LotID_ext_num     || '<null>')."\n".
	 '  $self->LotID_checkletter() '.($s->LotID_checkletter || '<null>')."\n".
	 '  $self->CheckLetter_valid() '.($s->CheckLetter_valid || '<null>')."\n".
         '  $self->DevID_mask()        '.($s->DevID_mask        || '<null>')."\n".
         '  $self->LotID_scribe(01)    '.($s->LotID_scribe(1)   || '<null>')."\n".
	 "\n";
       
}

## ------------------------------------------------------------- ##
sub LotID_spec { return $LotID_spec; }
## ------------------------------------------------------------- ##
##   returns the regular expression used to validate LotID

## ------------------------------------------------------------- ##
sub DevID_spec { return $DevID_spec; }
## ------------------------------------------------------------- ##
##   returns the regular expression used to validate DevID

## ------------------------------------------------------------- ##
sub Calc_check_letter {
## ------------------------------------------------------------- ##
##  calculates correct check letter for LotID                    ## 
	my $lotid = shift;
	my $LotID_spec = q/^(([A-Z]{1,2})([0-9]{5}))\.(([0-9]{1,2})([A-Z]{0,1})){0,1}$/;

	if ($lotid =~ /$LotID_spec/) {
	    my $lotid_number = $3;
	    my $lotid_ext_num = $5;

           return calc_chk_let ($lotid_number, $lotid_ext_num)
	} else {
           return undef;
        }
}

## ------------------------------------------------------------- ##
sub calc_chk_let {
## ------------------------------------------------------------- ##
##  Calculates check letter using PROMIS formula                 ##
         my $lotid_number = shift;
         my $lotid_ext_num = shift;
	my @checkletter = qw(F K R X C J N W A H L T Y);
        my $check_pointer = (((3*($lotid_number%13))+($lotid_ext_num%13))%13);
	return $checkletter[$check_pointer];
}

## ------------------------------------------------------------- ##
sub Calc_scribe {
## ------------------------------------------------------------- ##
## calculates scribe for given LotID and wafer number

    my $lotid = shift;
    my $wafid = shift;

    return undef unless $lotid =~ /$LotID_spec/;
    my $parent = $1;

    return calc_scribe($lotid, $wafid);
}

## ------------------------------------------------------------- ##
sub calc_scribe {
## ------------------------------------------------------------- ##
## calculates scribe for given lot and waf
##   ATMC:   D12345.1A.01A1
##   OHTFAB:   E12345.1A.01
##   Crolles: A111AAA-11A1

    my $LotID_spec = q/^(([A-Z]{1,2})([0-9]{5}))\.?(([0-9]{1,2})([A-Z]{0,1})){0,1}$/;

    my $lot   = shift;			# D12345
    my $waf   = shift;			# 1
    my $foundryid = shift;		# A111AAA
    my $dev = shift;
    return undef unless $lot =~ /$LotID_spec/;
    my $parent = $1;
    my $fabid  = $2;
    my $lotnum = $3;

	my $ocr = get_ocr_string($dev,$lot,$waf);
        return $ocr if $ocr;

    my $fab = $IDtoFAB{$fabid};
    my $scribe = '';

    $waf = sprintf "%02d", $waf if $waf eq '0' || $waf > 0;     # waf=01

    if ($fab eq 'Crolles') {

	my $foundryid  = $foundryid || get_foundryid($lot);

	# Add code for UMC ----- Jiandong 2008/04/09
        if(substr($foundryid,0,4) eq "UMC-"){
		$fab = 'UMC';
		$foundryid = substr($foundryid,4,5);
                $scribe  = "${foundryid}${waf}-";       # A111AAA11-
        }elsif(substr($foundryid,0,5) eq "CSM7-"){
		$fab = 'CSM7';
		$foundryid = substr($foundryid,5,6);
		$scribe  = "${foundryid}.${waf}";       # A111AAA.11
	}else{

                $scribe  = "${foundryid}-${waf}";       # A111AAA-11
        }
	
	return undef if ! $foundryid || $foundryid eq 'NULL';

    } elsif ( $fab eq 'OHTFAB' || $fab eq 'ATMC') {

	my $chk     = calc_chk_let($lotnum,1);
    	$scribe  = "${parent}.1${chk}.${waf}";  # A11111.1A.11

    } elsif ( $fab eq 'CHDFAB' ) {

        my $chk     = calc_chk_let($lotnum,1);
        $scribe  = "${parent}.1${chk} ${waf}"; 

    } elsif ( $fab eq 'Charter' ) {

    	$scribe  = "${parent}.1 ${waf}";  # YK11111.1 11

    } elsif ( $fab eq 'TLS' ) {

	my $year = get_ldtyear($lot);
	# print "ldtyear: $year \n";
	return undef if ! $year || $year eq 'NULL';
	my $header = calc_header($parent,$year);
	$scribe  = "${header}.${parent}.${waf}-";   # 2-9.BE12345.11- 

    } else { # use lot_id from ocr fablot, if it exists

	my $foundryid  = $foundryid || get_foundryid($lot);
    	$scribe  = "${foundryid}-${waf}";  	# LOTID-25

	return undef if ! $foundryid || $foundryid eq 'NULL';
    }

    $scribe .= SEMI_M12_checkletters("$scribe") 
		if $FABScribeChecksum{$fab} eq 'SEMI_M12';

    $scribe .= SEMI_checkletters("$scribe")
                if $FABScribeChecksum{$fab} eq 'SEMI';


    return $scribe;                 
}

## ------------------------------------------------------------- ##
sub SEMI_M12_checksum {
## ------------------------------------------------------------- ##
##  Calculates scribe check sum value

        my( $scribe, $sum, $n1, $n2, $n3, @letters, $ch );

        $scribe = shift;                        ## D12345.1A.01A1

        @letters = split //, $scribe;           # split each char
        $sum = 0;

        for $ch (@letters) {

          $n1  = ($sum + $sum) % 59;
          $n2  = ($n1 + $n1) % 59;
          $n3  = ($n2 + $n2) % 59;
          $sum = ($n3 + ord($ch) - 32 ) % 59;
        }

        return $sum;
}

## ------------------------------------------------------------- ##
sub SEMI_M12_checkletters {
## ------------------------------------------------------------- ##
##  Calculates scribe check letters

        my( $scribe, $chk, $sum, $bits_A, $bits_0, $diff);

        $scribe = shift;                        ## D12345.1A.01
        $scribe =~ s/[A-Z][0-9]$//;             # strip any checksum

        $chk = 'A0';

        $sum = SEMI_M12_checksum($scribe . $chk);

        return $chk if $sum ==0;

        $diff   = 59 - $sum;
        $bits_0 = $diff & 0x07;                 ## bits 0-2 of $sum
        $bits_A = ($diff & 0x38) >> 3;          ## bits 3-5 of $sum

        $chk = chr( ord('A') + $bits_A ).
               chr( ord('0') + $bits_0 );

        return $chk;
}

## ------------------------------------------------------------- ##
sub SEMI_checksum {
## ------------------------------------------------------------- ##
##  Calculates scribe check sum value

        my( $scribe, $sum, $n1, $n2, $n3, @letters, $ch );

        $scribe = shift;                        ## D12345.1A.01A1
        @letters = split //, $scribe;           # split each char
        $sum = 0;
        $n2 = @letters;
        for $ch (@letters) {

	  $n1 = ord($ch);
          $sum = 8 * (ord($ch) - 32  + $sum);
	  $sum = $sum % 59;
        }

        return $sum;
}

## ------------------------------------------------------------- ##
sub SEMI_checkletters {
## ------------------------------------------------------------- ##
##  Calculates scribe check letters

        my( $scribe, $chk, $sum, $bits_A, $bits_0, $diff);

        $scribe = shift;                        ## D12345.1A.01
        $scribe =~ s/[A-Z][0-9]$//;             # strip any checksum

        $chk = 'A';

        $sum = SEMI_checksum($scribe . $chk);

	$sum    = $sum + 16;
	$sum    = $sum % 59;
	#return $chk if $sum ==0;
        return "A0" if $sum ==0;

        $diff   = 59 - $sum;

        $bits_A = (($diff >> 3 ) & 0x7);          ## bits 3-5 of $sum
	$bits_0 = $diff & 0x7 ;                      ## bits 0-2 of $sum 
	
        $chk = chr( ord('A') + $bits_A ).
               chr( ord('0') + $bits_0 );

#	print "chk: $chk \n";
        return $chk;
}

## ------------------------------------------------------------- ##
sub get_foundryid {
## ------------------------------------------------------------- ##
##  Calculates scribe check letters

	my ($foundryid, $lot, $lotid, $partname, $ldtyear);

	$lot = shift;

	open FD, $OCR_FABLOT or return undef;
	my @lines = grep { (split)[0] =~ /^$lot/ } <FD>;
	close FD;

	($lotid, $partname, $foundryid, $ldtyear) = split(' ', $lines[0]);

	return $foundryid;
}

## ------------------------------------------------------------- ##
sub get_ldtyear {
## ------------------------------------------------------------- ##
##  Calculates scribe check letters

        my ($foundryid, $lot, $lotid, $partname, $ldtyear);

        $lot = shift;

        open FD, $OCR_FABLOT or return undef;
        my @lines = grep { (split)[0] =~ /^$lot/ } <FD>;
        close FD;

        ($lotid, $partname, $foundryid, $ldtyear) = split(' ', $lines[0]);

        return $ldtyear;
}

##------------------------------------------------------------- ##
## Added by Jiandong on 2009-06-24. for TLS's part                ##
sub calc_header {
## ------------------------------------------------------------ ##
##  Calculates header for TLS 

	my($parent) = shift;
	my($year) = shift;
	my $Y = substr($year,length($year)-1);
	my $MLAKey = calc_MLAKey($parent);
	my $header = "${MLAKey}-${Y}";
	return $header;
 
}

##------------------------------------------------------------- ##
## Added by Jiandong on 2009-06-24. for TLS's part                ##
sub calc_MLAKey {
## ------------------------------------------------------------ ##
##  Calculates MLAKey for TLS

	my($parent) = shift;
        my $lMla = substr($parent,2,length($parent));
        $lMla = $lMla * 7;
        my @chars = split("","$lMla");
        my $result = 20;
	my $char;
        foreach $char(@chars){
                $result += unpack("C*",$char);
        }
        my $hexSum = sprintf("%x", $result);
        my $lastDigit = substr("$hexSum",length($hexSum)-1);
        $lastDigit = hex($lastDigit);
        $lastDigit -= 10        if $lastDigit > 9;
        return $lastDigit;

}

## ------------------------------------------------------------- ##
sub get_ocr_string {
## ------------------------------------------------------------- ##
##  Looks in results_map tree for .OCRID.TXT file produced by EVR

        my $dev = shift;
        my $lot = shift;
        my $waf = shift;

        my($floor, $filename, $line, $wid, $ocr, @parts);

        $floor = $ENV{'SCFCMOUNT'} || '/floor';

        $filename = join('/', $floor, 'data', 'results_map', $dev, $lot, '.ocr', "r_1-$waf");
        if (-r $filename) {
          if (open(FD, $filename)) {
                $ocr = <FD>;
                close FD;
                chomp($ocr);
                return $ocr;
          }
        }
=prod no evr gen this file ----Liuzx 2016/6/27
        $filename = join('/', $floor, 'data', 'results_map', $dev, $lot, '.OCRDATA.TXT');
        return undef unless -r $filename;

        open(FD, $filename) || return undef;
        while($line=<FD>) {
                ($wid, $ocr) = split(' ', $line);
                chomp($ocr);
                if ($wid =~ /-${waf}$/) {
                        return $ocr;
                }
        }
        close FD;
=cut
        return undef;
}

1;

__END__

=head1 NAME


LotSpec - parsing and validation of Probe Lot and Device


This module provides OO routines to parse and validate
the format of Freescale Lot ID's and Device names.


=head2 SYNOPSIS

    use lib '/exec/apps/lib/perl5';
#    use lib '/exec/apps/lib/perl5_zz';
    use LotSpec;

    $spec = new LotSpec;			# Lot added later

      -- or --

    $spec = new LotSpec( LOT );			# No device

      -- or --

    $spec = new LotSpec( DEVICE, LOT );		# Both Device and Lot


  ## change lot or device

    $spec->LotID( LOT );			# sets new LotID
    $spec->DevID( DEVICE );			# sets new DevID


  ## validate

    my $lot_is_valid = $spec->LotID_valid;	# 1=true; <null>=false;
    my $dev_id_valid = $spec->DevID_valid;	# 1=true; <null>=false;
    my $chklet_valid = $spec->CheckLetter_valid # 1=true; <null>=false;

  ## query or parse

    my $lot  = $spec->LotID;			# DD12345.10D
    my $dev  = $spec->DevID;			# W00D00D

    my $mask = $spec->DevID_mask;		# D00D
    my $fact = $spec->LotID_fabid;              # DD
    my $fact = $spec->LotID_fab;                # ATMC

    my $par  = $spec->LotID_parent;		# DD12345
    my $num  = $spec->LotID_number;		# 12345
    my $ext  = $spec->LotID_ext;		# 10D
    my $extnum = $spec->LotID_ext_num;          # 10
    my $chklet = $spec->LotID_checkletter;      # D
    my $scribe = $spec->LotID_scribe(01);      	# D12345.1A.01A1

    my $letter = LotSpec::Calc_check_letter($lotid);
    my $scribe = LotSpec::Calc_scribe($lotid, wafer);

    my $chksum = LotSpec::SEMI_M12_checksum($scribe);		# 0=valid
    my $chklet = LotSpec::SEMI_M12_checkletters($scribe);	# 2 digits

	Note, checksum and checkletters calculated per SEMI M12-0998


  ## information and debug

    print LotSpec::LotID_spec; 		# prints reg-exp used to validate lot 
    print LotSpec::DevID_spec;		# prints reg-exp used to validate device

    print $spec->bist;			# prints all query/parse information

     ie:
  	$self->{LotID}  DD12345.10A
  	$self->{DevID}  W13L93S

  	$self->LotID_valid()       1
  	$self->DevID_valid()       1
	$self->LotID_fabid()       DD
	$self->LotID_fab()         ATMC
  	$self->LotID_parent()      DD12345
  	$self->LotID_number()      12345
  	$self->LotID_ext()         10D
        $self->LotID_ext_num()     10
  	$self->LotID_checkletter() A
  	$self->CheckLetter_valid() 1
  	$self->DevID_mask()        L93S
  	$self->LotID_scribe('01')  DD12345.1A.01A1


=head2 AUTHORS


    Contributor:
	Richard Daniel <richard.daniel@freescale.com>

=head2 COPYRIGHT AND LICENSE


Copyright 2004 Austin Test Data Sysetms, Freescale Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
