#!/usr/local/bin/perl5
my ($input)=map{ /(.*)/; $1 } @ARGV;
print SEMI_M12_checkletters($input);
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
