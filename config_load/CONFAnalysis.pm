package CONFAnalysis;

=cut
Usage: this is an object used to analysis config file which like structure as below:
A {
	B {
		C:D
		...
	}
	E {
		F:G
		H:I
		 :J   <=  will be added to H, should be parsed as H:IJ 
	}
	...
}
...
Notice: Using OOP in perl, inherit from CONF_Block object. Please reading Reference in perl, just like Pointer in C++.
Analysis CONF structure into 2 type of elements, one is hash, storage key&value, the other is CONF_Block object.

Examples:
	1. if you want get WA00N21B -> sort_2 -> hot you may use 
		$value = $config->block('WA00N21B')->block{'sort_2'}->key('hot');
	2. if you want to get blocks named "NlLayer" array, you may use:
		@NlLayerArray = $config->blocks('NlLayer'); of cause its an array.
	3. if you want to get all blocks, just $config->blocks();
	4. if you want to get all keys in this block, you can use
		@keys = $config->keys();
	5. if you want to get a known key 'hot', you can use
		$value_of_hot = $config->key('hot');

=cut

use Data::Dumper; # use Dumper for debug. Without any dependency relationship
use CONF_Block;

@ISA = qw(CONF_Block);

sub new {
	my $self = CONF_Block->new('Root');
	bless $self;
	$self->{file} = "";
	return $self;
}

sub _trim {
	my $string = shift;
	$string =~ s/^\s*//g;
	$string =~ s/\s*$//g;
	return $string;
}

sub _tab_complement {
    my $tab = "";
    my $gradation = shift;
    for (my $i = $gradation; $i > 0; $i--) {
        $tab .= "\t";
    }
    return $tab;
}

sub _ErrorSynax {
	my ($CONF,$line_num,$content) = @_;
	warn "Error in Synax for $CONF, on $line_num, please check this line!! tips:$content\n";
}

sub LoadCONF {
	my $self = shift;
	my $CONF = shift;
	$self->{file} = $CONF;
	undef $self->{data};
	if (-f $CONF && -r _) {
		my $line_index = 0; # like a cursor in reading a file, record line number.
		my $line_last; #store last line of the config file
		my $gradation = 0; #stands for the gradation
		my $this_ref = $self; #cursor ref for store data
		my @current_ref;
		$current_ref[0] = $self;
		my $last_key = '';
		open(CONF,'<',$CONF) or warn "Fail to open File $CONF\n";
		while(my $line = <CONF>) {
			$line = _trim($line);
			$line_index ++;
			next if ($line =~ /^#/ || $line eq '' ) ;
			#{
			if ($line =~ /^\{$/) {
				$last_key = '';
				_ErrorSynax($CONF,$line_index,'strange structure') if ($line_last =~ /[\{\:\}]/);				
				my $temp_ref = CONF_Block->new($line_last);
				$this_ref->push_data($temp_ref);
				$this_ref = $temp_ref;
				$gradation ++;
				$current_ref[$gradation] = $this_ref;
				#}
			} elsif ($line =~ /^\}$/) {
				$last_key = '';
				$gradation --;
				_ErrorSynax($CONF,$line_index,'gradation nagtive') if ($gradation < 0);
				$this_ref = $current_ref[$gradation] ;
				#** {
			} else {
				if ($line =~ /^([^:\{\}\s]+)\s*\{$/) {
					$last_key = '';
					my $type = $1;
					my $temp_ref = CONF_Block->new($type);
					$this_ref->push_data($temp_ref);
					$this_ref = $temp_ref;
					$gradation ++;
					$current_ref[$gradation] = $this_ref;
					#***:*****
				} elsif ( $line =~ /^([^:\{\}\s]+)\s*:([^\{\}]*)$/ ) {
					my $_ref = {};
					$_ref->{key} = $1;
					$_ref->{value} = $2;
					$this_ref->push_data($_ref);
					$last_key = $_ref->{key};
					#****:*****}
				} elsif ( $line =~ /^([^:\{\}\s]+)\s*:([^\{\}]*)\s*\}$/) {
					my $_ref = {};
					$_ref->{key} = $1;
					$_ref->{value} = $2;
					$this_ref->push_data($_ref);
					$last_key = $_ref->{key};
					$gradation --;
					_ErrorSynax($CONF,$line_index,'gradation nagtive') if ($gradation < 0);
					$this_ref = $current_ref[$gradation];
					#*******          
				} elsif ($line =~ /^[^:\{\}]+$/) {  
					$last_key = '';
					#did nothing if $line = A; (without any :,{ })
					#:********
				} elsif ($line =~ /^:([^\{\}]+)$/) {
					_ErrorSynax($CONF,$line_index,'last key missing') if ($last_key eq '');
					my $_ref = {};
					$_ref->{key} = $last_key;
					$_ref->{value} = $1;
					$this_ref->push_data($_ref);
					#????
				} else {
					_ErrorSynax($CONF,$line_index,'Unkown type line');
				}
			}
			$line_last = $line;
		}
		close CONF;
	} else {
		warn "$CONF is not a normal file or readable! Please have a check\n";
	}
}



sub WriteConfig { # not finish
	my $self = shift;
	my $output_file = shift;
	local $text = "";
	if (-f $output_file && ! -w _) {
		warn "could not write file $output_file!\n";
	}
	&BlockDump($self->{data},0);
	open(CONF,'>',$output_file) or warn "Fail to open File $CONF\n";
	print CONF $text;
	close(CONF);
}

sub BlockDump {
	my $block = shift;
	my $gradation = shift;
	foreach my $ele (@$block) {
		my $space = &_tab_complement($gradation);
		if (ref $ele eq "HASH") {
			$text .= $space . $ele->{key} . ":" . $ele->{value} . "\n";
		} elsif (ref $ele eq "CONF_Block") {
			$text .= $space . $ele->{name} . " \n" . $space . "{\n";
			$gradation++;
			&BlockDump($ele->{data},$gradation);
			$text .= $space . "}\n";
			$gradation--;
		} else {
			warn "Illegal reference $ele\n";
		}
		
	}
}


return 1;
