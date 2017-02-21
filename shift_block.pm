#!/usr/local/bin/perl5
#######################################################################
#Usage:  input time output shift;
#Author: LiuZX
#Date:   2016/4/1
######################################################################
#Example:
# my $shift=shift_block->new();
# Get shift:
# print $shift->getshift(1454342409);
# Change shift card:
# $shift->select_card('/exec/apps/bin/lib/perl5/shift_card/shift_card2016');
#######################################################################
package shift_block;
use Data::Dumper;
#use File::Basename;
#use Cwd 'abs_path';
sub new {
	my $class = shift;
	my $self = {};
	$self->{card};
	bless $self,$class;
	$self->{unit}=&_loadcard();
	return $self;
}
#print &getshift('1454342409');
sub sel_card{
	my $self=shift; 	
	my $card=shift;	
	$self->{card}=$card;
	$self->{unit}=&_loadcard();
#	print Dumper($self->{unit});
}
sub _loadcard{
	my $self=shift;
	my $card=$self->{card};
	if ($card eq ''){
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time());	
	$year+=1900;
#	my $path=abs_path($0);
	$card="/exec/apps/bin/lib/perl5/shift_card/shift_card$year";
#	print $card;
	}
	my $unit={};
	open(CARD,"<$card") or warn $!;
	while(my $line=<CARD>){
		next if $line=~ /\#/;
   		my @line=split(/\:/,$line);
   		my @shift=split(/\s+/,$line[1]);
		unshift @shift,'#';
        	$unit->{$line[0]}=\@shift;
		}
	close CARD;
#	print Dumper($unit);
	return $unit;
}
sub getshift{
	my $self=shift;
	my $time=shift;
	return "None Value" if ($time eq '');
	my $unit={};
	$unit=$self->{unit};
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($time);
#month start on 0
	$mon+=1;
	$hour=$hour-8;
	my $result;
	if ( $hour >= '0' and $hour < '12' ){
		$result=$unit->{$mon}[$mday];
	}elsif( $hour >='12' ){
		$result=&_night_shift($unit->{$mon}[$mday]);
	}elsif( $hour <'0'){
		if ($mday =='1'){
			return "undefine month:$mon-1" unless defined $unit->{$mon-1};
			$ref=$unit->{$mon-1};
			$mday=@$ref-1;	
			$result=&_night_shift($unit->{$mon-1}[$mday]);
		}else{
#		print $unit->{$mon}[$mday-1];
			$result=&_night_shift($unit->{$mon}[$mday-1]);
		}
	}
	return $result;
}
sub _night_shift{
	my $shift=shift;
	return 'ERROR' if ($shift eq '');
        if ($shift eq "A"){
              return "B";
        }elsif($shift eq "B"){
              return "A";
        }elsif($shift eq "C"){
              return "D";
        }elsif($shift eq "D"){
              return "C";
        }else{
              return "N:".$shift;
        }
}
1;
