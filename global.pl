#!/usr/bin/perl

# Configure MARTE XMI tags dependent on Modelio version

our (@Hardware, @LE1Core);
our ($Hardware, $ComputingResource, $Processor, $Alloc);
our ($hr_attribute_name, $hcr_attribute_name, $hp_attribute_name, $a_attribute_name);

# Define the XMI MARTE tags to use
sub setup_marte {
    my $modelio_version = shift(@_);

    if($modelio_version == 1.2) {
	$Hardware = 'MARTEMARTE_DesignModelHRMHwGeneral:HwResource';
	$ComputingResource = 'MARTEMARTE_DesignModelHRMHwLogicalHwComputing:HwComputingResource';
	$Processor = 'MARTEMARTE_DesignModelHRMHwLogicalHwComputing:HwProcessor';
	$Alloc = 'MARTEMARTE_FoundationsAlloc:Allocate';

	$hr_attribute_name = 'base_Element';
	$hcr_attribute_name = 'base_Element';
	$hp_attribute_name = 'base_Element';
	$a_attribute_name = 'base_Dependency';

	return 0;
    }
    elsif($modelio_version == 2.2) {
	$Hardware = 'HwGeneral:HwResource'; #TODO: find out what this tag is, probably HwGeneral:HwResource
	$ComputingResource= 'HwComputing:HwComputingResource';
	$Processor = 'HwComputing:HwProcessor';
	$Alloc = 'Alloc:Allocate';

	$hr_attribute_name = 'base_Classifier';
	$hcr_attribute_name = 'base_Classifier';
	$hp_attribute_name = 'base_Property';
	$a_attribute_name = 'base_Dependency';

	return 0;
    }
    else {
	# Unsupported Modelio version
	return -1;
    }
}

sub count_le1_cores
{
    my $le1 = shift(@_);
    my $LE1 = XMLin($le1, KeyAttr=>['list'], ForceArray=>1);

    my $homog = 0;
    if($LE1->{'type'}[0] eq 'homogeneous') {
	$homog = 1;
    }

    my $num = 0;

    # read number of systems
    my $sys = $LE1->{'systems'}[0];
    for(my $s=0;$s<$sys;++$s) {
	# read number of contexts
	my $cnt = $LE1->{'system'}[$s]->{'contexts'}[0];

	if($homog) {
	    # Read only the first context and multiply through
	    my $hcnt = $LE1->{'system'}[$s]->{'context'}[0]->{'HYPERCONTEXTS'}[0];
	    $num += ($sys * $cnt * $hcnt);
	    last;
	}
	else {
	    # Loop through and count all hypercontexts
	    for(my $c=0;$c<$cnt;++$c) {
		my $hcnt = $LE1->{'system'}[$s]->{'context'}[$c]->{'HYPERCONTEXTS'}[0];
		$num += $hcnt;
	    }
	}
    }
    return $num;
}

our ($in, $out, $le1, $top, $svg);
sub parse_args
{
    for(my $i=0;$i<@_;++$i) {
	if($_[$i] =~ /^-in?$/) {
	    $in = $_[++$i];
	}
	elsif($_[$i] =~ /^-l(e1)?$/) {
	    $le1 = $_[++$i];
	}
	elsif($_[$i] =~ /^-o(ut)?$/) {
	    $out = $_[++$i];
	}
	elsif($_[$i] =~ /^-t(op)?$/) {
	    $top = {'name' => $_[++$i], 'id' => '', 'ref' => ''};
	}
	elsif($_[$i] =~ /^-s(vg)?$/) {
	    $svg = $_[++$i];
	}
	else {
	    print 'Unknown argument: ' . $_[$i] . "\n";
	}
    }
}

# Generate a hash of all elements using the xmi:id as a reference
# Arguments:
#  Hash reference for return data
#  XML reference
#  label string
sub get_objects
{
    my $o = shift(@_);
    my $m = shift(@_);
    my $name = shift(@_);

    if($m =~ /^HASH/) {
	foreach my $key (keys %{$m}) {
	    if($key eq 'xmi:id') {
		%$o->{$m->{$key}} = {'ref' => $m, 'element' => $name};
		if($m->{'name'} eq $top->{'name'}) {
		    $top->{'id'} = $m->{$key};
		    $top->{'ref'} = $m;
		}
	    }
	    if($m->{$key} =~ /^ARRAY/) {
		get_objects($o, $m->{$key}, $key);
	    }
	}
    }
    elsif($m =~ /^ARRAY/) {
	for(my $i=0;$i<(@{$m});++$i) {
	    get_objects($o, ${$m}[$i], $name);
	}
    }
    else {
    }
}

sub uniq {
    my %seen = ();
    my @r = ();
    foreach my $a (@_) {
        unless ($seen{$a}) {
            push @r, $a;
            $seen{$a} = 1;
        }
    }
    return @r;
}

sub getType
{
    my $h = shift(@_);
    my $software = 0;
    my $hardware = 0;
    foreach my $key (keys %{$h}) {
	if(grep $_ eq ${$h}{$key}, @Processor) {
	    $software = 1;
	}
	if(grep $_ eq ${$h}{$key}, @Hardware) {
	    $hardware = 1;
	}
    }
    if($software && $hardware) {
	return 'codesign';
    }
    elsif($software) {
	return 'software';
    }
    elsif($hardware) {
	return 'hardware';
    }

    return 'unknown';
}

# Wrapper for generating combinations of HASH
# Arguments:
#  Array reference for return data
#  Hash of data {{label => [...]}, {label2 => [...]} ... }
sub combi
{
    my $return_array = shift(@_);
    my %data = @_;
    my %temp;
    _combi(0, $return_array, \%temp, %data);
    undef(%temp);
}

# Generate all possibly combinations of passed hash
# Arguments:
# iterator
# array pointer, return data
# hash pointer, temporary storage for recursion
# data (HASH)
sub _combi
{
    my $d = shift(@_);
    my $aP = shift(@_);
    my $cP = shift(@_);
    my %data = @_;

    my $i = 0;
    my $part;
    foreach my $_part (sort keys %data) {
	if($i++ == $d) {
	    $part = $_part;
	    last;
	}
    }

    for(my $i=0;$i<@{$data{$part}};$i++) {
	$$cP{$part} = $data{$part}[$i];
	if($d == (keys(%data)-1)) {
	    push (@$aP, {%{$cP}});
	}
	else {
	    _combi(($d+1), $aP, $cP, %data);
	}
    }
}

# Calculate whether current config would result in a deadlock
# Follow the control from from start to end and make sure objects aren't placed on cores used earlier in the chain
sub follow_control_flow
{
    my $name = shift(@_);
    my $dir = shift(@_);
    my $i = shift(@_);
    my $prev = shift(@_);
    my $seen = shift(@_);
    my $ok = shift(@_);

    if($all[$i]->{$name} ne $prev) {
	${$seen}{$prev} = 1;
	if(${$seen}{$all[$i]->{$name}}) {
	    $$ok = 0;
	}
    }
    foreach my $out (@{${$dir}{$name}->{'out'}}) {
	follow_control_flow($out, $dir, $i, $all[$i]->{$name}, $seen, $ok);
    }
}

1;
