#!/usr/bin/perl

# set allocations and generate xmi file of statically mapped model

use strict;
use XML::Simple;
use XML::Writer;
use Data::Dumper;

my ($alloc, $a_attribute_name);
my $modelio_version = 2.2;

if($modelio_version == 1.2) {
    $alloc = 'MARTEMARTE_FoundationsAlloc:Allocate';
    $a_attribute_name = 'base_Dependency';
}
elsif($modelio_version == 2.2) {
    $alloc = 'Alloc:Allocate';
    $a_attribute_name = 'base_Dependency';
}
else {
    print 'Unknown Modelio version: ' . $modelio_version . "\n";
    exit(-1);
}

my $xmiFile = $ARGV[0];
my $xmlFile = $ARGV[1];
my $mappingID = $ARGV[2];

# get the mapping from the xmlFile
my $xml = XMLin($xmlFile, KeyAttr=>['list'], ForceArray=>1);

# check that the mappingID passed exists
my $mapI = -1;
my $currentMap;
while(my $map = $xml->{'mappings'}[0]->{'mapping'}[++$mapI]) {
    if($map->{'id'} eq $mappingID) {
	$currentMap = $map;
    }
}

if(!defined($currentMap)) {
    print 'Could not find mapping with ID: ' . $mappingID . "\n";
    exit -1;
}


#print Dumper($currentMap);

# now have the mapping specified
# read in the xmi file, find the allocations sections
# find the dependencies they link to
# reread the file, remove the dependencies and allocations
# add $currentMap->{'map'} dependencies and allocations
# (think about renaming other MARTE tags?)
my $xmi = XMLin($xmiFile, KeyAttr=>['list'], ForceArray=>1);

my %dep_alloc;

# capture the dependencies and remove the allocations
my $allocationI = -1;
while(my $allocation = $xmi->{$alloc}[++$allocationI]) {
    $dep_alloc{$allocation->{$a_attribute_name}} = $allocation->{'xmi:id'};
    delete($xmi->{$alloc}[$allocationI]);
}

# remove the depedencies associated with allocations
my $model = $xmi->{'uml:Model'}[0];
my $pEI = -1;
while(my $packagedE = $model->{'packagedElement'}[++$pEI]) {
    if(($packagedE->{'xmi:type'} eq 'uml:Dependency') && (defined($dep_alloc{$packagedE->{'xmi:id'}}))) {
	delete($model->{'packagedElement'}[$pEI]);
    }

# remove the clientDependencies from packagedElements
    my @clientDep = split(/\s+/, $packagedE->{'clientDependency'});
    delete($packagedE->{'clientDependency'});
    my $cD = '';
    foreach my $clientDep (@clientDep) {
	if(!defined($dep_alloc{$clientDep})) {
	    if($cD ne '') { $cD .= ' '; }
	    $cD .= $clientDep;
	}
    }
    if($cD) {
	$packagedE->{'clientDependency'} = $cD;
    }


# remove the clientDependencies from ownedAttributes
    my $oAI = -1;
    while(my $ownedA = $packagedE->{'ownedAttribute'}[++$oAI]) {
	my @clientDep = split(/\s+/, $ownedA->{'clientDependency'});
	delete($ownedA->{'clientDependency'});
	my $cD = '';
	foreach my $clientDep (@clientDep) {
	    if(!defined($dep_alloc{$clientDep})) {
		if($cD ne '') { $cD .= ' '; }
		$cD .= $clientDep;
	    }
	}
	if($cD) {
	    $ownedA->{'clientDependency'} = $cD;
	}
    }
}

# create new allocations and dependencies, set clientDependencies
my $mapI = -1;
while(my $map = $currentMap->{'map'}[++$mapI]) {
    # create an allocation
    push(@{$xmi->{$alloc}}, {'xmi:id' => 'autogenerated_allocation_' . $mapI,
			     $a_attribute_name => 'autogenerated_dependency_' . $mapI});
    # create a dependency
    push(@{$model->{'packagedElement'}}, {'xmi:type' => 'uml:Dependency',
					  'xmi:id' => 'autogenerated_dependency_' . $mapI,
					  'supplier' => $map->{'end'},
					  'client' => $map->{'start'}});
    # set clientDependencies
    my $pEI = -1;
    while(my $packagedE = $model->{'packagedElement'}[++$pEI]) {
	my $oAI = -1;
	while(my $ownedA = $packagedE->{'ownedAttribute'}[++$oAI]) {
	    if($ownedA->{'xmi:id'} eq $map->{'start'}) {
		$ownedA->{'clientDependency'} = 'autogenerated_dependency_' . $mapI;
	    }
	}
    }
}

my $temp = XMLout($xmi, rootname => 'xmi:XMI', XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>');
print $temp;
exit(0);