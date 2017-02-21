package CONF_Block;

sub new {
	my $self = {};
	bless $self;
	shift;
	my $name = shift;
	$self->{name} = $name;
	$self->{data} = ();
	return $self;
}

sub push_data {
	my $self = shift;
	my $data = shift;
	push @{$self->{data}}, $data;
}

sub _pop_data {
	my $self = shift;
	pop @{$self->{data}};
}
sub get_data_by_index {
	my $self = shift;
	my $index = shift;
	return ${$self->{data}}[$index];
}

sub get_data_array {
	my $self = shift;
	return @{$self->{data}};
}

sub blocks {
	my $self = shift;
	my $block_name = shift;
	my @blocks = ();
	foreach my $ref ($self->get_data_array()) {
		if (ref $ref eq "CONF_Block") {
			if ($block_name eq "" ) {
				push @blocks, $ref;
			} else {
				if ($ref->{name} eq $block_name) {
					push @blocks, $ref;
				}
			}
		}
	}
	return @blocks;
}
sub mask_block { 
	my $self = shift;
        my $block_name = shift;
	die "Please input block name to get Block" if ($block_name eq "");
	my $result;
	my $match=0;
	my $last_match=0;
	foreach my $ref ($self ->get_data_array()) { 
		if (ref $ref eq "CONF_Block") {
			my $mask=$ref->{name};
			$mask=~ s/\+/\.\{1\}/g;
                                if ( $block_name =~ /$mask/) {
					$result=$ref if ($result eq "");
					$last_match=$match;
					$match=($ref->{name}=~ s/\+/\+/g);
					if ($match lt $last_match) {
						$result=$ref;
					}
                                }
                 }
	}
	return $result;
}
sub keys {
	my $self = shift;
	my @keys = ();
	foreach my $ref ($self->get_data_array()) {
		if (ref $ref eq "HASH") {
			push @keys, $ref;
		}
	}
	return @keys;
}

sub block {
	my $self = shift;
	my $block_name = shift;
	die "Please input block name to get Block" if ($block_name eq "");
	foreach my $ref ($self->get_data_array()) {
		if (ref $ref eq "CONF_Block" && $ref->{name} eq $block_name) {
			return $ref;
		}
	}
	return;
}

sub key {
	my $self = shift;
	my $key_name = shift;
	die "Please input block name to get Block" if ($key_name eq "");
	my @value;
	foreach my $ref ($self->get_data_array()) {
		if (ref $ref eq "HASH" && $ref->{key} eq $key_name) {
			push @value, $ref->{value};
		}
	}
	if (@value == 0 ) {
		return ();
	} elsif (@value == 1) {
		return $value[0];
	} else {
		return @value;
	}
}
1;
