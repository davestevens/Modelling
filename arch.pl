#!/usr/bin/perl

# Configure architecture section of UML model

use strict;
use XML::Simple;
use Data::Dumper;

our ($Hardware, $ComputingResource, $Processor, $Alloc);
our ($hr_attribute_name, $hcr_attribute_name, $hp_attribute_name, $a_attribute_name);

my (@Application, @Part, @Hardware, @ComputingResource, @Processor);
my @app;
my @arch;
my @mapping;

require "global.pl";

setup_marte(2.2);

our ($in, $out, $le1, $top);
parse_args(@ARGV);

# Check arguments have been set
if(($in eq '') || ($le1 eq '') || ($out eq '')) {
    print 'You have not specified all required files.' . "\n";
    exit(-1);
}

# Read input XMI file
my $XMI = XMLin($in, KeyAttr=>['list'], ForceArray=>1);
my $Model = $XMI->{'uml:Model'}[0];

# Create a hash of all xmi:ids
my %Objects;
get_objects(\%Objects, $XMI, 'TOP');

# Read $Hardware elements
my $architectureI = -1;
while(my $HwResource = $XMI->{$Hardware}[++$architectureI]) {
    push(@Hardware, $HwResource->{$hr_attribute_name});
    push (@{$arch[0]{'hardware'}}, {'name' => $Objects{$HwResource->{$hr_attribute_name}}->{'ref'}->{'name'},
				    'id' => $HwResource->{$hr_attribute_name}});
}

# Read $ComputingResouce elements and $Processors
my $architectureI = -1;
while(my $HwComputingResource = $XMI->{$ComputingResource}[++$architectureI]) {
    push(@ComputingResource, $HwComputingResource->{$hcr_attribute_name});
    push (@{$arch[0]{'computingresource'}}, {'name' => $Objects{$HwComputingResource->{$hcr_attribute_name}}->{'ref'}->{'name'},
					     'id' => $HwComputingResource->{$hcr_attribute_name},
					     'core' => []});

    # need to look for cores
    my $packagedElement = $Objects{$HwComputingResource->{$hcr_attribute_name}}->{'ref'};
    my $ownedAttributeI = -1;
    while(my $ownedAttribute = $packagedElement->{'ownedAttribute'}[++$ownedAttributeI]) {
	# Find this core as a HwProc
	my $coresI = -1;
	while(my $HwProcessor = $XMI->{$Processor}[++$coresI]) {
	    if($HwProcessor->{$hp_attribute_name} eq $ownedAttribute->{'xmi:id'}) {
		# Check multiplicity
		my $mult = 1;
		if(defined($ownedAttribute->{'upperValue'})) {
		    $mult = $ownedAttribute->{'upperValue'}[0]->{'value'};
		}
		push(@Processor, $HwProcessor->{$hp_attribute_name});
		push (@{$arch[0]{'computingresource'}[0]{'core'}}, {'name' => $ownedAttribute->{'name'},
								    'id' => $HwProcessor->{$hp_attribute_name},
								    'multiplicity' => $mult,
								    'type' => $ownedAttribute->{'type'}});
	    }
	}
    }
}

# Count number of Processors within ComputingResource
if(defined(@{$arch[0]{'computingresource'}})) {
    # Check for multiplicites within architecture
    my $coresI = -1;
    my %wildcard;
    while(my $core = $arch[0]->{'computingresource'}[0]->{'core'}[++$coresI]) {
	if($core->{'multiplicity'} eq '*') {
	    %wildcard = %{$core};
	}
    }

    if(!%wildcard) {
	# Nothing to be extended
	print 'Nothing to be extended.' . "\n";
	exit 1;
    }
    else {
	# Perform replacement of this core
	my $cores = count_le1_cores($le1);
	my $xmi_cores = @{$arch[0]->{'computingresource'}[0]->{'core'}};
	if($xmi_cores > $cores) {
	    print 'More cores in XMI than in LE1 model.' . "\n";
	    exit 2;
	}

	# Remove allocs to wildcard core
	my $allocationI = -1;
	while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
	    # need to then look up for a dependency with this $a_attribute_name;
	    my $dependencyI = -1;
	    while(my $dependency = $Model->{'packagedElement'}[++$dependencyI]) {
		if(($dependency->{'xmi:type'} eq 'uml:Dependency')
		   &&
		   ($dependency->{'xmi:id'} eq $allocation->{$a_attribute_name})) {
		    if($dependency->{'supplier'} eq $wildcard{'id'}) {
			# Remove this dependency and allocation
			splice(@{$Model->{'packagedElement'}}, $dependencyI--, 1);
			splice(@{$XMI->{$Alloc}}, $allocationI--, 1);
		    }
		}
	    }
	}
	# Remove wildcard core
	# Find ComputingResource
	my $pEI = -1;
	while(my $packagedE = $Model->{'packagedElement'}[++$pEI]) {
	    if($packagedE->{'xmi:id'} eq $arch[0]->{'computingresource'}[0]->{'id'}) {
		# Remove core
		my $oAI = -1;
		while(my $ownedA = $packagedE->{'ownedAttribute'}[++$oAI]) {
		    if($ownedA->{'xmi:id'} eq $wildcard{'id'}) {
			splice(@{$packagedE->{'ownedAttribute'}}, $oAI--, 1);
			last;
		    }
		}
	    }
	}
	# Remove MARTE stereotype
	my $cI = -1;
	while(my $hwp = $XMI->{$Processor}[++$cI]) {
	    if($hwp->{$hp_attribute_name} eq $wildcard{'id'}) {
		splice(@{$XMI->{$Processor}}, $cI--, 1);
	    }
	}

	# create $cores - (($xmi_cores - 1)) new cores
	my @temp;
	for(my $i=0;$i<($cores - ($xmi_cores-1));++$i) {
	    push(@temp, {'xmi:type' => 'uml:Property',
			 'xmi:id' => 'autogen_Processor_i' . $i,
			 'name' => $wildcard{'name'} . '_' . $i,
			 'type' => $wildcard{'type'},
			 'aggregation' => 'composite'});
	}

	# Connect to ComputingResource
	my $pEI = -1;
	while(my $packagedE = $Model->{'packagedElement'}[++$pEI]) {
	    if($packagedE->{'xmi:id'} eq $arch[0]->{'computingresource'}[0]->{'id'}) {
		push(@{$packagedE->{'ownedAttribute'}}, @temp);
		last;
	    }
	}

	# Create MARTE stereotypes
	for(my $i=0;$i<($cores - ($xmi_cores-1));++$i) {
	    push(@{$XMI->{$Processor}}, {'xmi:id' => 'autogen_Processor_i' . $i . '_MARTE',
					 $hp_attribute_name => 'autogen_Processor_i' . $i});
	}
    }
}
# else insert new architecture
else {
    # Read LE1 XML config file
    my $cores = count_le1_cores($le1);

    # Create a base class to be used as LE1Core
    push(@{$Model->{'packagedElement'}}, {'xmi:type' => 'uml:Class',
					  'xmi:id' => 'autogen_Processor_baseClass',
					  'name' => 'autogen_Processor_base'});
    # Tag this as a $Processor
    push(@{$XMI->{$Processor}}, {'xmi:id' => 'autogen_Processor_MARTE',
				 $hp_attribute_name => 'autogen_Processor_baseClass'});


    # Create a single ComputingResource class with $cores attributes
    {
	my @temp;
	for(my $i=0;$i<$cores;++$i) {
	    push(@{$temp[0]}, {'xmi:type' => 'uml:Property',
			       'xmi:id' => 'autogen_Processor_i' . $i,
			       'name' => 'i' . $i,
			       'type' => 'autogen_Processor_baseClass',
			       'aggregation' => 'composite'});
	}

	push(@{$Model->{'packagedElement'}}, {'xmi:type' => 'uml:Class',
					      'xmi:id' => 'autogen_ComputingResource',
					      'name' => 'autogen_ComputingResource',
					      'ownedAttribute' => @temp});

	# MARTE stereotypes
	push(@{$XMI->{$ComputingResource}}, {'xmi:id' => 'autogen_ComputingResource_MARTE',
					     $hcr_attribute_name => 'autogen_ComputingResource'});
	for(my $i=0;$i<$cores;++$i) {
	    push(@{$XMI->{$Processor}}, {'xmi:id' => 'autogen_Processor_i' . $i . '_MARTE',
					 $hp_attribute_name => 'autogen_Processor_i' . $i});
	}
    }


    # Create a single alloc from Top Level Class to this generated ComputingResource
    push(@{$XMI->{$Alloc}}, {'xmi:id' => 'autogen_allocation',
			     $a_attribute_name => 'autogen_dependency'});

    # create a dependency
    push(@{$Model->{'packagedElement'}}, {'xmi:type' => 'uml:Dependency',
					  'xmi:id' => 'autogen_dependency',
					  'supplier' => 'autogen_ComputingResource',
					  'client' => $top->{'id'}});

}

# Output to file
open FILE, "> $out" or die 'Could not open file: ' . $out . ' (' . $! . ')' . "\n";
print FILE XMLout($XMI, rootname => 'xmi:XMI', XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>');
close FILE;

exit 0;
