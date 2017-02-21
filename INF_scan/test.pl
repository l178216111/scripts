#!/usr/local/bin/perl5
my $file='/floor/data/results_map/WA00N59H-HOT/C72620.45Y/r_1-25';         
$cmd = "grep SESSION_RESULTS $file";
        $lines = `$cmd`;
        @line = split(/\n/,$lines);
print $lines;
        @tmp_results = split(/:/,$line[0]);
        $session_results = $tmp_results[1];
        if($session_results =~ /.*PROCESSED$/){
		print "integrator";
        }
