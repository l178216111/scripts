#!/usr/local/bin/perl5
=pod
Write By JiangNan, add a default logic for RDS.
divide wafermap into 2x4 pieces as below, and compare the yield of their edge dice
    ###
## 1 # 2 ##
###########
## 3 # 4 ##
    ###
&&
    ###
## # 6 # ##
## 5 # 7 ##
## # 8 # ##
    ###	
=cut
my $defaultDelta = 0.6;
sub DefaultYieldCheck {
	my $msg;
	my $wafer_id;
	my ($device,$lot,$pass) = @_;
	my $inf_dir="/floor/data/results_map";
	 $inf_dir.= "/$device/$lot/";
	my %output;
	opendir(INFDIR,$inf_dir);
	my @files = readdir(INFDIR);
	@files = map {$inf_dir . $_ } grep { $_ =~ /^r_1-\d\d?$/ } @files;
	closedir INFDIR;
	my $inf;
	my $interrupt;
	foreach $inf (sort @files) {
	undef @GoodBin;
	undef @RowData;
	open (FILE,$inf);
	while ($line = <FILE>){
		if ($line=~/SESSION_RESULTS:.*INTERRUPTED\s*$/){
			$interrupt='1';
			last;
		};
		$wafer_id=$1 if ($line=~/SLOT:(\d*)/);
		if ($line=~/strKeyword:PSBN/){
	  	my $pass_row=0;
			while($line !~/StBinTable/){
				if($line=~ /ListData/){
				my @temp =split(/:/,$line);
				$passbin[$pass_row]=$temp[1];
				$pass_row++
				}
			$line = <FILE>; 
	  		}			
	  }
	my $m=0;
        if ($line =~ /iBinCodeLast/){            # To match the iBinCodeLast
		 my $n = 0;                           # n is set for Row number 
	        while ($line !~ /NlFormat/){      # if not match NlFormat will get the RowData lines
     	        if ($line =~ /RowData/){          
	        	@temp = split (/:/,$line);
				$m[$n]=$temp[1];	    
				$n++;
			} 
			$line = <FILE>;          # To get a new line 		   
	       }
	       $m++;                             # m is set for map number 	   
		}	
	}
	close FILE;
	next if ($interrupt=='1');
##get goodbin
	for ($i=0;$i<@passbin;$i++){
	my $line = $passbin[$i];
	my @split_line = split(//,$line);
		for ($j=0;$j<@split_line;$j++) {
			my $bin = $i * 32 + $j;
			if ($split_line[$j] == 1) {
				push @GoodBin,$bin;
			}
		}
	}
##end
	@RowData=@m;
		my @MatrixData = prune(\@RowData);
		#print Dumper(\@MatrixData);
		my @edge = getEdge(\@MatrixData);
		#print Dumper(\@edge);
		my @part2 = @{$edge[0]};
		my @part3 = @{$edge[1]};
		my @part4 = @{$edge[2]};
		my @part1 = @{$edge[3]};
	
		my @part5,@part6,@part7,@part8;
		for($i=0;$i<@part1;$i++) {
			if ($i<@part1/2) {
				push @part5,$part1[$i];
			} else {
				push @part6,$part1[$i];
			}
		}
		for($i=0;$i<@part2;$i++) {
			if ($i<@part2/2) {
				push @part6,$part2[$i];
			} else {
				push @part7,$part2[$i];
			}
		}
		for($i=0;$i<@part3;$i++) {
			if ($i<@part3/2) {
				push @part7,$part3[$i];
			} else {
				push @part8,$part3[$i];
			}
		}
		for($i=0;$i<@part4;$i++) {
			if ($i<@part4/2) {
				push @part8,$part4[$i];
			} else {
				push @part5,$part4[$i];
			}
		}
		
		#print Dumper(\@part5);
=pod
		$part1=scalar @part1;
		$part2=scalar @part2;
		$part3=scalar @part3;
		$part4=scalar @part4;
		$part5=scalar @part5;
		$part6=scalar @part6;
		$part7=scalar @part7;
		$part8=scalar @part8;
		print "$part1,$part2,$part3,$part4,$part5,$part6,$part7,$part8\n";
=cut
		
		my $yield1,$yield2,$yield3,$yield4,$yield5,$yield6,$yield7,$yield8;
		#print Dumper(\@part2);
#		print Dumper(\@GoodBin);
		$yield1 = getYield(\@part1,\@GoodBin);
		$yield2 = getYield(\@part2,\@GoodBin);
		$yield3 = getYield(\@part3,\@GoodBin);
		$yield4 = getYield(\@part4,\@GoodBin);
		$yield5 = getYield(\@part5,\@GoodBin);
		$yield6 = getYield(\@part6,\@GoodBin);
		$yield7 = getYield(\@part7,\@GoodBin);
		$yield8 = getYield(\@part8,\@GoodBin);
		
	#	print "$yield1\n$yield2\n$yield3\n$yield4\n$yield5\n$yield6\n$yield7\n$yield8\n";
		
		if ($yield1 - $yield4 > $defaultDelta) {
			$output{$wafer_id}= "top left shift:top left =$yield1,bottom right=$yield4\n";
		} elsif ($yield4 - $yield1 > $defaultDelta) {
			$output{$wafer_id}="right down shift:top left =$yield1,bottom right=$yield4\n";
		}
		if ($yield2 - $yield3 > $defaultDelta) {
			$output{$wafer_id}= "right top shift:top right=$yield2,bottom left=$yield3\n";
		} elsif ($yield3 - $yield2 > $defaultDelta) {
			$output{$wafer_id}="left down shift::top right=$yield2,bottom left=$yield3\n\n";
		}
		if ($yield6 - $yield8 > $defaultDelta) {
			$output{$wafer_id} ="top shift:top=$yield6,bottom=$yield8\n";
		} elsif ($yield8 - $yield6 > $defaultDelta) {
			$output{$wafer_id}= "bottom shift:top=$yield6,bottom=$yield8\n";
		}
		if ($yield5 - $yield7 > $defaultDelta) {
			$output{$wafer_id}= "left shift:left=$yield5,right=$yield7\n";
		} elsif ($yield7 - $yield5 > $defaultDelta) {
			$output{$wafer_id}= "right shift:left=$yield5,right=$yield7\n";
		}
		
#		foreach my $unit (@edge) {
#			my $x = $unit->{x} + 2; # 2 shift
#			my $y = $unit->{y} + 2; # 2 shift
#			print "$x,$y,$unit->{bin}\n";
#		}
#		print Dumper(\@edge);	
	}
#print %output;
return %output;
}

sub prune {

	my $before = shift;
	my @TempRowData = @$before;
	#print Dumper($before);
	my @after;
	#left
	my $shiftx = 0;
	#up
	my $shifty = 0;
	#right
	my $dropx = 0;
	#down
	my $dropy = 0;
	
	my $ColumnLength = scalar(split(/\s/,$TempRowData[0]));
	my $RowLength = scalar @TempRowData;
#	print "Row=$RowLength;Column=$ColumnLength\n";

	for ($i=0;$i<$RowLength;$i++) {
		my $ValidRow=0;
		my $ele;
		foreach $ele (split(/\s/, $TempRowData[$i])) {
			if ($ele ne '__' && $ele ne '@@' ) {
				$ValidRow = 1;
				last;
			}
		}
		if ($ValidRow == 0) {
			push @InvalidRow, $i;
		}
	}
	
	for ($j=0;$j<$ColumnLength;$j++) {
		my $ValidColumn = 0;
		my $Row;
		foreach  $Row (@TempRowData) {
			my $ele = (split(/\s/,$Row))[$j];
			if ( $ele ne '__' && $ele ne '@@' ) {
				$ValidColumn = 1;
				last;
			}
		}
		if ($ValidColumn == 0) {
			push @InvalidColumn, $j ;
		}
	}
	
	for($i=0;$i<@InvalidRow;$i++) {
		if ($i == $InvalidRow[$i]) {
			$shifty++;
		} else {
			last;
		}
	}
	
	for($i=@InvalidRow-1;$i>0;$i--) {
		if ( $RowLength - @InvalidRow + $i == $InvalidRow[$i]) {
			$dropy++;
		} else {
			last;
		}
	}
	
	for($i=0;$i<@InvalidColumn;$i++) {
		if ($i == $InvalidColumn[$i]) {
			$shiftx++;
		} else {
			last;
		}
	}
	for($i=@InvalidColumn-1;$i>0;$i--) {
		if ( $ColumnLength - @InvalidColumn + $i == $InvalidColumn[$i]) {
			$dropx++;
		} else {
			last;
		}
	}
	
#	print "shiftx=$shiftx,shifty=$shifty,dropx=$dropx,dropy=$dropy\n";	
#	print Dumper(\@TempRowData);
	my $flagx = 0;
	for ($i=$shifty;$i<@TempRowData-$dropy;$i++) {
		my @row = split(/\s/,$TempRowData[$i]);
		my $number=@row;
		for ($j=$shiftx;$j<@row-$dropx;$j++) {
			if( $row[$j] eq '__' || $row[$j] eq '@@' ) {
				$after[$j-$shiftx][$i-$shifty] = '@@';
			} else {
				$after[$j-$shiftx][$i-$shifty] = $row[$j];
			}
		}
	}
	
=debug
	my @output;
	foreach my $x (@after) {
		push @output, join(' ',@$x);
	}
	print Dumper(\@output);
=cut
	#print Dumper(\@after);
	return @after
}

sub getEdge {
	my $ref = shift;
	my @MatrixData = @$ref;
	my $xlength = scalar @MatrixData;
	my $ylength = scalar @{$MatrixData[0]}; 
	my $halfx = int($xlength/2); 
	my $halfy = int($ylength/2);
	my @edge; # all edge dice
	my @part1; # lefttop edge dice
	my @part2; # righttop edge dice
	my @part3; # rightbottom edge dice
	my @part4; # leftbottom edge dice
	my %leftEdge; #each line minimum edge coordinate
	my %rightEdge;#each line maximum edge coordinate	
	# get the furthest die for each line on right&left;
	for($j=0;$j<$ylength;$j++) {
		for($i=$xlength;$i>=$halfx;$i--) {
			if(isTestDie($MatrixData[$i][$j])) {
				$rightEdge{$j} = $i;
				last;
			}
		}	
		for($i=0;$i<$halfx;$i++) {
			if(isTestDie($MatrixData[$i][$j])) {
				$leftEdge{$j} = $i;
				last;
			}
		}
	}
	for($j=0;$j<$ylength;$j++) {
		my $right;
		my $left;	
		if ($j==0 || $j==$ylength-1 ) {
			$right = int($xlength/2);
			$left = int($xlength/2) - 1;
			#PRINT ":RIGHT=$RIGHT;left=$left,xlength=$xlength,ylength=$ylength\n";
		} elsif($j<$halfy) {# for top half wafer, need to compare with previous line
			$right = $rightEdge{$j-1} + 1;
			$left = $leftEdge{$j-1} - 1;
		} else {  # for bottom half wafer, need to compare with next line
			$right = $rightEdge{$j+1} + 1;
			$left = $leftEdge{$j+1} - 1;
		}
		if ($j<$halfy) {
			#top right quarter, add Edge dice for each line ouside of for loop because I want to ensure all edge die can be added, even if ...
			for($i=$right;$i<$rightEdge{$j};$i++) {
				if(isTestDie($MatrixData[$i][$j])) {
					add2Edge(\@part2,$i,$j,$MatrixData[$i][$j]);
				} else {
					my $nj = $j;
					while(!isTestDie($MatrixData[$i][$nj])) {
					 $nj++;
					last if ($MatrixData[$i][$nj]=="");
					}
					# should be test die from here
					add2Edge(\@part2,$i,$nj,$MatrixData[$i][$nj]) if  ($MatrixData[$i][$nj] !="");
				}
			}
			add2Edge(\@part2,$rightEdge{$j},$j,$MatrixData[$rightEdge{$j}][$j]);
			
			#top left quarter.
			for($i=$left;$i>$leftEdge{$j};$i--) {
				if(isTestDie($MatrixData[$i][$j])) {
					add2Edge(\@part1,$i,$j,$MatrixData[$i][$j]);
				} else {
					my $nj = $j;
					while(!isTestDie($MatrixData[$i][$nj])) {
						$nj++;
					last if ($MatrixData[$i][$nj]=="");
					}
					# should be test die from here
					add2Edge(\@part1,$i,$nj,$MatrixData[$i][$nj]) if  ($MatrixData[$i][$nj] !="");
				}
			}
			add2Edge(\@part1,$leftEdge{$j},$j,$MatrixData[$leftEdge{$j}][$j]);
			
		} else {
			#bottom right quarter.
			add2Edge(\@part3,$rightEdge{$j},$j,$MatrixData[$rightEdge{$j}][$j]);
			for($i=$rightEdge{$j}-1;$i>$right;$i--) {
				if(isTestDie($MatrixData[$i][$j])) {
					add2Edge(\@part3,$i,$j,$MatrixData[$i][$j]);
				} else {
					my $nj = $j;
					while(!isTestDie($MatrixData[$i][$nj])) {
						$nj--;
					last if ($MatrixData[$i][$nj]=="");
					
					}
					# is test die from now
					add2Edge(\@part3,$i,$nj,$MatrixData[$i][$nj]) if  ($MatrixData[$i][$nj] !="");
				}
			}
			
			#bottom left quarter.
			add2Edge(\@part4,$leftEdge{$j},$j,$MatrixData[$leftEdge{$j}][$j]);
			for($i=$leftEdge{$j}+1;$i<$left;$i++) {
				if(isTestDie($MatrixData[$i][$j])) {
					add2Edge(\@part4,$i,$j,$MatrixData[$i][$j]);
				} else {
					my $nj = $j;
					while(!isTestDie($MatrixData[$i][$nj])) {
						$nj--;
						last if ($MatrixData[$i][$nj]=="");
					}
					# is test die from now
					add2Edge(\@part4,$i,$nj,$MatrixData[$i][$nj]) if  ($MatrixData[$i][$nj] !="");
				}
			}
		}
	}
	
	# need reverse part1 & part4
	@part1_reverse = reverse(@part1);
	@part4_reverse = reverse(@part4);
	
=pod	#
	print "---- part1 ----\n";
	foreach my $unit (@part1) {
		my $x = $unit->{x} + 2; # 2 shift
		my $y = $unit->{y} + 2; # 2 shift
		print "before: $x,$y,$unit->{bin}\n";
	}
	print "---- part1 ----\n";
	print "---- part1_tmp ----\n";
	foreach my $unit (@part1_tmp) {
		my $x = $unit->{x} + 2; # 2 shift
		my $y = $unit->{y} + 2; # 2 shift
		print "before: $x,$y,$unit->{bin}\n";
	}
	print "---- part1_tmp ----\n";
	print "---- part2 ----\n";
	foreach my $unit (@part2) {
		my $x = $unit->{x} + 2; # 2 shift
		my $y = $unit->{y} + 2; # 2 shift
		print "before: $x,$y,$unit->{bin}\n";
	}
	print "---- part2 ----\n";
	print "---- part3 ----\n";
	foreach my $unit (@part3) {
		my $x = $unit->{x} + 2; # 2 shift
		my $y = $unit->{y} + 2; # 2 shift
		print "before: $x,$y,$unit->{bin}\n";
	}
	print "---- part3 ----\n";
	print "---- part4 ----\n";
	foreach my $unit (@part4) {
		my $x = $unit->{x} + 2; # 2 shift
		my $y = $unit->{y} + 2; # 2 shift
		print "before: $x,$y,$unit->{bin}\n";
	}
	print "---- part4 ----\n";
	#
=cut	
	@edge = (\@part2,\@part3,\@part4_reverse,\@part1_reverse);
	return @edge;	

=pod	abandoned by Nan.
	# half top wafer
	for($i=0;$i<$end_x;$i++) {
	
		# 1/4 right&top wafer
		for($j=$start_y;$j<$ylength;$j++) {
			my @point = ($i,$j,$MatrixData[$i][$j]);
			if(isTestDie($MatrixData[$i][$j])) {
				push @part2, \@point ;
				$start_y = $j;
				if(isTestDie($MatrixData[$i][$j+1])) {		
				} else {
					for ($ni=$i+1;$ni<$end_x;$ni++) {
						if(isTestDie($MatrixData[$ni][$j+1])) {
							last;
						} else {
							my @point = ($ni,$j,$MatrixData[$ni][$j]);
							push @part2, \@point;
						}
					}
				}
				
			} else {
				for ($ni=$i+1;$ni<$end_x;$ni++) {
					my @point = ($ni,$j,$MatrixData[$ni][$j]);
					if(isTestDie($MatrixData[$ni][$j])) {
						push @part2, \@point ;
						$start_y = $j;
						last;
					}
				}
			}

		
		# 1/4 left&top wafer
		for ($j=0;$j<$start_y;$j++) {
			my @point = ($i,$j,$MatrixData[$i][$j]);
			if($i == 0) {
				push @part1, \@point if($MatrixData[$i][$j] ne '__' && $MatrixData[$i][$j] ne '@@' );
			} else {
				
			}
		}
		
	}
	
	# half bottom wafer
	for($i=$endx;$i<$xlength;$i++) {
	
	}
=cut	

=pod	abandoned 
	while ($i<$xlength) {
		while($j<$ylength) {
			# if the die have already calculated, jump out
			if ($i == $start_i && $j = $start_j) {
				$i=$xlenth;
				last;
			}
			my $quarter = getQuarter($i,$j,$xlength,$ylength);
			if ($quarter == 1) {
				
			} elsif ($quarter == 2) {
				if (isTestDie($MatrixData[$i][$j])) {
					if ($i==0) {
						add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
						#$calculated{$i}{$j} = 1;
						$j++;
						$last_direction = 'r';
					} elsif ($j==$ylength-1) {
						add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
						#$calculated{$i}{$j} = 1;
						$i++;
						$last_direction = 'd';
					} else {
						if ($last_direction eq 'd') {
							if (isTestDie($MatrixData[$i][$j+1])) {
								$j++;
								$last_direction = 'r';
							} elsif (isTestDie($MatrixData[$i+1][$j])) {
								add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
								$i++;
								$last_direction = 'd';
							} elsif (isTestDie($MatrixData[$i][$j-1])) {
								add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
								$j--;
								$last_direction = 'l';
							} else {
								
								#
								#raiseError('strange die,$i,$j!\n');
							}
						} elsif ($last_direction eq 'r') {
							if (isTestDie($MatrixData[$i-1][$j])) {
								$i--;
								$last_direction = 'u';
							} elsif (isTestDie($MatrixData[$i][$j+1])) {
								add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
								$j++;
								$last_direction = 'r';
							} elsif (isTestDie($MatrixData[$i+1][$j])) {
								add2Edge(\@edge,$i,$j,$MatrixData[$i][$j]);
								$i++;
								$last_direction = 'd';
							} else {
								raiseError('strange die,$i,$j!\n');
							}
						} elsif {
						} elsif {
							$j++;
						}
						
					}
				} else {
					if ($last_direction eq 'r') {
						$j--;
						$i++;
						$last_direction = 'd';
					}
				}
				
			} elsif ($quarter == 3) {
			
			} elsif ($quarter == 4) {
			
			} else {
				raiseError;
			}
		}
	}
=cut
	
}

sub isEdgeInkonly {
	my ($ref,$i,$j) = @_;
	my @Matrix = @$ref;
	my $xlength = scalar @Matrix;
	if ($i > $xlength/2) {
		for($x=$i;$x<$xlength;$x++) {
			return 0 if(isTestDie($Matrix[$x][$j]));
		}
	} else {
		for($x=$i;$x>0;$i--) {
			return 0 if(isTestDie($Matrix[$x][$j]));
		}
	}
	return 1;
}

sub isTestDie {
	my $value = shift;
	return 0 if ($value eq '@@' || $value eq '__' || $value eq '');
	return 1 if (hex($value) >= 0 && hex($value) < 256) ; # assert all value not @@ & __ are test dice;
	return 0;
}

sub getQuarter {
	my ($x,$y,$xlength,$ylength) = @_;
	if ($x > $xlength/2) {
		if ($y > $ylength/2) {
			return 3 # lower right quarter 
		} else {
			return 4 # lower left quarter
		}
	} else {
		if ($y > $ylength/2) {
			return 2 # higher right quarter 
		} else {
			return 1 # higher left quarter 
		}
	}
}

# parameter: @edge,x,y,bin
sub add2Edge {
	my ($array_ref,$x,$y,$bin) = @_;
	my $unit = {};
	$unit->{x} = $x;
	$unit->{y} = $y;
	$unit->{bin} = hex($bin);
	push @$array_ref,$unit;
}

sub getYield {
	($point_ref,$goodbin_ref) = @_;
	my $good;
	my $count;
	my %goodbin;
	my $bin;
	foreach $bin(@$goodbin_ref) {
		$goodbin{$bin} = 1;
	}
	my $ele;
	foreach $ele (@$point_ref) {
		if(exists $goodbin{$ele->{bin}}) {
			$good++
		} 
		$count++;
	}
#	print "good=$good,count=$count\n";
	return sprintf('%.3f', $good / $count);
}

sub raiseError {
	my $msg = shift;
	die $msg;
}

1;
