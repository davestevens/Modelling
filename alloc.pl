#!/usr/bin/perl

# read allocations and generate xml file of possible/defined allocations
# (ModelIO xmi only (XMI: 2.4.18.7008, MARTE: 1.2.22.7008) MAYBE?)

use strict;
use XML::Simple;
use Data::Dumper;

our ($Hardware, $ComputingResource, $Processor, $Alloc);
our ($hr_attribute_name, $hcr_attribute_name, $hp_attribute_name, $a_attribute_name);

require "global.pl";

setup_marte(2.2);

my $deadlock = 0;
our ($in, $out, $top, $svg);
parse_args(@ARGV);

my %Allocations;
our (@Application, @Part, @Hardware, @ComputingResource, @Processor);

# Check arguments have been set
if(($in eq '') || ($out eq '')) {
    print 'You have not specified all required files.' . "\n";
    exit -1;
}
if($top->{'name'} eq '') {
    print "No top level class defined\n";
    exit 2;
}

# Read input XMI file
my $XMI = XMLin($in, KeyAttr=>['list'], ForceArray=>1);
my $Model = $XMI->{'uml:Model'}[0];

my %Objects;
# Create a hash of all xmi:ids
get_objects(\%Objects, $XMI, 'TOP');

my @app;
my @arch;
my @mapping;

# Loop over model, find toplevelclass and print the application
if($top->{'id'} eq '') {
    print 'Could not find top level class: ' . $top->{'name'} . "\n";
    exit 3;
}
else {
    my $packagedElement = $Objects{$top->{'id'}}->{'ref'};
    push (@app, {'name' => $packagedElement->{'name'}, 'id' => $packagedElement->{'xmi:id'}, 'part' => []});
    push(@Application, $packagedElement->{'xmi:id'});
    # now to print the parts
    my $ownedAttributeI = -1;
    while(my $ownedAttribute = $packagedElement->{'ownedAttribute'}[++$ownedAttributeI]) {
#	if($ownedAttribute->{'xmi:type'} ne 'uml:Port') {
	push(@Part, $ownedAttribute->{'xmi:id'});
	push (@{$app[0]{'part'}}, {'name' => $ownedAttribute->{'name'},
				   'type' => $Objects{$ownedAttribute->{'type'}}->{'ref'}->{'name'},
				   'id' => $ownedAttribute->{'xmi:id'}});
#	}
    }
}

# Now find the architecture
# Need to first see if there is a Hardware block
my $found = 0;

my $architectureI = -1;
while(my $HwResource = $XMI->{$Hardware}[++$architectureI]) {
    push(@Hardware, $HwResource->{$hr_attribute_name});
    push (@{$arch[0]{'hardware'}}, {'name' => $Objects{$HwResource->{$hr_attribute_name}}->{'ref'}->{'name'},
				    'id' => $HwResource->{$hr_attribute_name}});
    $found++;
}

# Then ComputingResource
my $architectureI = -1;
while(my $HwComputingResource = $XMI->{$ComputingResource}[++$architectureI]) {
    push(@ComputingResource, $HwComputingResource->{$hcr_attribute_name});
    push (@{$arch[0]{'computingresource'}}, {'name' => $Objects{$HwComputingResource->{$hcr_attribute_name}}->{'ref'}->{'name'},
					     'id' => $HwComputingResource->{$hcr_attribute_name},
					     'core' => []});

    # need to look for cores
    # find this ComputingResource class and get the property values
    my $packagedElementI = -1;
    my %Attributes;
    while(my $packagedElement = $Model->{'packagedElement'}[++$packagedElementI]) {
	if($packagedElement->{'xmi:id'} eq $HwComputingResource->{$hcr_attribute_name}) {
	    my $ownedAttributeI = -1;
	    while(my $ownedAttribute = $packagedElement->{'ownedAttribute'}[++$ownedAttributeI]) {
		# Find this core as a HwProc
		my $coresI = -1;
		while(my $HwProcessor = $XMI->{$Processor}[++$coresI]) {
		    if(($HwProcessor->{$hp_attribute_name} eq $ownedAttribute->{'xmi:id'})
		       &&
		       ($HwProcessor->{$hp_attribute_name} ne '')){
			push(@Processor, $HwProcessor->{$hp_attribute_name});
			push (@{$arch[0]{'computingresource'}[0]{'core'}}, {'name' => $ownedAttribute->{'name'},
									    'id' => $HwProcessor->{$hp_attribute_name}});
			last;
		    }
		}
	    }
	}
    }
    $found++;
}

if(!$found) {
    print 'Could not find any architecture components' . "\n";
    exit 4;
}

my %dir;
my $first;

# Calculate the control flow of the application
if($deadlock) {
# Find all connectors
    my @direction;
    foreach my $key (keys %Objects) {
	if($Objects{$key}->{'element'} eq 'ownedConnector') {
	    # Foreach end
	    my $endI = -1;
	    push(@direction, {});
	    while(my $end = $Objects{$key}->{'ref'}->{'end'}[++$endI]) {
		# name of port
		my $port = $Objects{$end->{'role'}}->{'ref'};
		# type
		my $interface = $Objects{$port->{'type'}}->{'ref'};
		# Search usage, if this is a client in any then its a required port
		my $required = 0;
		foreach my $key (keys %Objects) {
		    if(($Objects{$key}->{'ref'}->{'xmi:type'} eq 'uml:Usage')
		       &&
		       ($Objects{$key}->{'ref'}->{'client'} eq $interface->{'xmi:id'})) {
			$required = 1;
			last;
		    }
		}
		# Find containing object
		my $part = $Objects{$end->{'partWithPort'}}->{'ref'};
		if($required) {
		    $direction[$#direction]{'required'} = $part->{'name'};
		}
		else {
		    $direction[$#direction]{'provided'} = $part->{'name'};
		}
	    }
	}
    }

# Create a direction hash
    my $packagedElement = $Objects{$top->{'id'}}->{'ref'};
    my $ownedAttributeI = -1;
    while(my $ownedAttribute = $packagedElement->{'ownedAttribute'}[++$ownedAttributeI]) {
	$dir{$ownedAttribute->{'name'}} = {'in' => [], 'out' => []};
    }

    foreach my $d (@direction) {
	push(@{$dir{$d->{'required'}}->{'out'}}, $d->{'provided'});
	push(@{$dir{$d->{'provided'}}->{'in'}},$d->{'required'});
    }
# Traverse
    foreach my $key (keys %dir) {
	if(!@{$dir{$key}->{'in'}}) {
	    $first = $key;
	}
    }
}

my %b;
my @orig_mapping = {'id' => 'orig',
		    'type' => '',
		    'multicore' => '',
		    'map' => []};

# Loop through allocations
if($#Part >= 0)  {
# Get allocations from parts
    my $allocationI = -1;
    while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
	# need to then look up for a dependency with this $a_attribute_name;
	my $dependency = $Objects{$allocation->{$a_attribute_name}}->{'ref'};
	push (@{$orig_mapping[0]{'map'}}, {'start' => $dependency->{'client'},
					   'end' => $dependency->{'supplier'},
	      });
	if(grep $_ eq $dependency->{'client'}, @Part) {
	    # check if already defined as an array in the hash
	    if(!defined($b{$dependency->{'client'}})) {
		$b{$dependency->{'client'}} = [];
	    }

	    # push to the array specifying the supplier
	    if(grep $_ eq $dependency->{'supplier'}, @Hardware) {
		push (@{$b{$dependency->{'client'}}}, $dependency->{'supplier'});
	    }
	    elsif(grep $_ eq $dependency->{'supplier'}, @ComputingResource) {
		# get all cores in the system
		for(my $i=0;$i<@Processor;$i++) {
		    push (@{$b{$dependency->{'client'}}}, $Processor[$i]);
		}
	    }
	    elsif(grep $_ eq $dependency->{'supplier'}, @Processor) {
		push (@{$b{$dependency->{'client'}}}, $dependency->{'supplier'});
	    }
	    else {
		# problem
		# unknown supplier
	    }
	}
    }

    my @unalloc_part;
# Create a list of unallocated parts
    for(my $j=0;$j<@Part;++$j) {
	if(!defined($b{$Part[$j]})) {
	    push(@unalloc_part, $Part[$j]);
	}
    }

# get allocations from application
    my $allocationI = -1;
    while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
	# need to then look up for a dependency with this $a_attribute_name;
	my $dependency = $Objects{$allocation->{$a_attribute_name}}->{'ref'};
	if(grep $_ eq $dependency->{'client'}, @Application) {
	    for(my $j=0;$j<@unalloc_part;$j++) {
		# check if already defined as an array in the hash
		if(!defined($b{$unalloc_part[$j]})) {
		    $b{$unalloc_part[$j]} = [];
		}

		# push to the array specifying the supplier
		if(grep $_ eq $dependency->{'supplier'}, @Hardware) {
		    push (@{$b{$unalloc_part[$j]}}, $dependency->{'supplier'});
		}
		elsif(grep $_ eq $dependency->{'supplier'}, @ComputingResource) {
		    # get all cores in the system
		    for(my $i=0;$i<@Processor;$i++) {
			push (@{$b{$unalloc_part[$j]}}, $Processor[$i]);
		    }
		}
		elsif(grep $_ eq $dependency->{'supplier'}, @Processor) {
		    push (@{$b{$unalloc_part[$j]}}, $dependency->{'supplier'});
		}
		else {
		    # problem
		    # unknown supplier
		}
	    }
	}
    }
}

# type of orig_mapping
my $type = getType(@{$orig_mapping[0]{'map'}});
$orig_mapping[0]{'type'} = $type;
$orig_mapping[0]{'multicore'} = ((@Processor > 1) && ($type ne 'hardware')) ? 'true' : 'false';

# remove any duplicate array items
foreach my $part (sort keys %b) {
    @{$b{$part}} = &uniq(@{$b{$part}});
}

my @all;
if(keys(%b) == 0) {
    push (@mapping, {'count' => 0,
		     'warning' => 'No Allocations found'});
}
else {
# Calculate all possible combinations of allocations
    &combi(\@all, %b);

    if($deadlock) {
# Remove unusable permutations
	for(my $i=0;$i<@all;++$i) {
	    my %seen;
	    my $ok = 1;

	    # Follow control flow to work out if dead locks can occur
	    follow_control_flow($first, \%dir, $i, $all[$i]{$first}, \%seen, \$ok);

	    if(!$ok) {
		splice(@all, $i--, 1);
	    }
	}
    }

    if(keys(%b) < @Part) {
	push (@mapping, {'count' => ($#all+1),
			 'warning' => 'Unallocated parts in model (' . (@Part - keys(%b)) . ')',
			 'mapping' => []});
    }
    else {
	push (@mapping, {'count' => ($#all+1),
			 'mapping' => []});
    }

    push (@{$mapping[0]{'mapping'}}, @orig_mapping);

# loop over @all
    for(my $i=0;$i<@all;$i++) {
	my $type = getType($all[$i]);
	my @_mapping = {'id' => $i,
			'type' => $type,
			'multicore' => ((@Processor > 1) && ($type ne 'hardware')) ? 'true' : 'false',
			'map' => []};
	foreach my $key (keys %{$all[$i]}) {
	    push (@{$_mapping[0]{'map'}}, {'start' => $key, 'end' => $all[$i]{$key}});
	}
	push (@{$mapping[0]{'mapping'}}, @_mapping);
    }
}

# set up array to output XML
my @container;
push (@container, {'architecture' => @arch, 'application' => @app, 'mappings' => @mapping});
open FILE, "> $out" or die 'Could not open file: ' . $out . "\n";
print FILE (XMLout(@container, XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>'));
close FILE;

if(defined($svg)) {
# Create output svg images
    my (@svg_app, @svg_compresc, @svg_hard);
    my ($max_width, $max_height);
    my ($numParts, $numCores, $numHardware);

    my $spacing = 15;
    my $font_size = 20;

    $numParts = @{$app[0]->{'part'}};

    if(defined($arch[0]->{'computingresource'}[0]->{'core'})) {
	$numCores = @{$arch[0]->{'computingresource'}[0]->{'core'}};
    }
    else {
	$numCores = 0;
    }

    if(defined($arch[0]->{'hardware'})) {
	$numHardware = @{$arch[0]->{'hardware'}};
    }
    else {
	$numHardware = 0;
    }

    my $x_offset = $spacing;
    my $y_offset = $spacing;
    my $width = 200;
    my $height = 30;
    my $space = 300;
    my @colors = ('black', 'darkblue', 'darkred', 'goldenrod', 'darkgreen', 'darkmagenta', 'deepskyblue', 'darkgrey', 'coral', 'blueviolet');
    my $color = -1;

    $max_width = (2 * ($width + $spacing)) + $space;

    # App name
    push(@svg_app, {'id' => $app[0]->{'id'},
		    'text' => {'x' => (($width + 10) / 2) + $x_offset - 5,
			       'y' => $y_offset + ($height / 1.25),
			       'font-family' => 'Verdana',
			       'font-size' => $font_size,
			       'text-anchor' => 'middle',
			       'content' => $app[0]->{'name'}
		    },
		    'rect' => {'x' => $x_offset - 5,
			       'y' => $y_offset,
			       'width' => $width + 10,
			       'height' => $height,
			       'fill' => 'lightgray',
			       'stroke' => 'black',
			       'stroke-width' => 2,
		    },
		    'g' => []});

    $y_offset += ($height + $spacing);
    my $pI = -1;
    while(my $part = $app[0]{'part'}[++$pI]) {
	push (@{$svg_app[0]{'g'}}, {'id' => $part->{'id'},
				    'rect' => {'x' => $x_offset,
					       'y' => $y_offset,
					       'width' => $width,
					       'height' => $height,
					       'fill' => 'white',
					       'stroke' => 'black',
					       'stroke-width' => 1,
				    },
				    'text' => {'x' => ($width / 2) + $x_offset,
					       'y' => $y_offset + ($height / 2),
					       'font-family' => 'Verdana',
					       'font-size' => $font_size/2,
					       'text-anchor' => 'middle',
					       'content' => $part->{'name'}}
	      });
	$y_offset += ($height + $spacing);
    }

    $max_height = ($y_offset + ($height + $spacing));

    # Reset x and y offsets
    $y_offset = $spacing;
    $x_offset += ($width + $space);

    # CompResc
    if($numCores > 0) {
	push(@svg_compresc, {'id' => $arch[0]->{'computingresource'}[0]->{'id'},
			     'text' => [{'x' => (($width + 10) / 2) + ($x_offset - 5),
					 'y' => $y_offset + ($height / 3),
					 'font-family' => 'Verdana',
					 'font-size' => $font_size/2,
					 'text-anchor' => 'middle',
					 'content' => '<<HwComputingResource>>'},
					{'x' => (($width + 10) / 2) + ($x_offset - 5),
					 'y' => $y_offset + ($height / 1.25),
					 'font-family' => 'Verdana',
					 'font-size' => $font_size/2,
					 'text-anchor' => 'middle',
					 'content' => $arch[0]->{'computingresource'}[0]->{'name'}}
				 ],
			     'rect' => {'x' => $x_offset - 5,
					'y' => $y_offset,
					'width' => $width + 10,
					'height' => $height,
					'fill' => 'lightgray',
					'stroke' => 'black',
					'stroke-width' => 2,
					'col' => $colors[++$color % @colors]
			     },
					    'g' => []});

	# cores
	$y_offset += ($height + $spacing);
	my $cI = -1;
	while(my $core = $arch[0]{'computingresource'}[0]->{'core'}[++$cI]) {
	    push (@{$svg_compresc[0]{'g'}}, {'id' => $core->{'id'},
					     'rect' => {'x' => $x_offset,
							'y' => $y_offset,
							'width' => $width,
							'height' => $height,
							'fill' => 'white',
							'stroke' => 'black',
							'stroke-width' => 1,
							'col' => $colors[++$color % @colors]
					     },
							    'text' => [{'x' => ($width / 2) + $x_offset,
									'y' => $y_offset + ($height / 3),
									'font-family' => 'Verdana',
									'font-size' => $font_size/2,
									'text-anchor' => 'middle',
									'content' => '<<HwProcessor>>'},
								       {'x' => ($width / 2) + $x_offset,
									'y' => $y_offset + ($height / 1.25),
									'font-family' => 'Verdana',
									'font-size' => $font_size/2,
									'text-anchor' => 'middle',
									'content' => $core->{'name'}}
							    ]
		  });
	    $y_offset += ($height + $spacing);
	}
    }

    # hardware
    if($numHardware > 0) {
	push(@svg_hard, {'id' => $arch[0]->{'hardware'}[0]->{'id'},
			 'text' => [{'x' => (($width + 10) / 2) + ($x_offset - 5),
				     'y' => $y_offset + ($height / 3),
				     'font-family' => 'Verdana',
				     'font-size' => $font_size/2,
				     'text-anchor' => 'middle',
				     'content' => '<<HwResource>>'},
				    {'x' => (($width + 10) / 2) + ($x_offset - 5),
				     'y' => $y_offset + ($height / 1.25),
				     'font-family' => 'Verdana',
				     'font-size' => $font_size/2,
				     'text-anchor' => 'middle',
				     'content' => $arch[0]->{'hardware'}[0]->{'name'}}
			     ],
			 'rect' => {'x' => $x_offset - 5,
				    'y' => $y_offset,
				    'width' => $width + 10,
				    'height' => $height,
				    'fill' => 'lightgray',
				    'stroke' => 'black',
				    'stroke-width' => 2,
				    'col' => $colors[++$color % @colors]
			 }});
	$y_offset += $font_size + (2 * $spacing);
    }

    # Check which is biggest
    my $app_h = $max_height;
    my $arch_h = $y_offset;

    if($app_h == $arch_h) {
	# Nothing
    }
    elsif($app_h > $arch_h) {
	# move arch down
	my $diff = ($app_h - $arch_h) / 2;
	$svg_compresc[0]{'text'}[0]->{'y'} += $diff;
	$svg_compresc[0]{'text'}[1]->{'y'} += $diff;
	$svg_compresc[0]{'rect'}->{'y'} += $diff;
	my $gI = -1;
	while(my $g = $svg_compresc[0]{'g'}[++$gI]) {
	    $g->{'rect'}->{'y'} += $diff;
	    $g->{'text'}[0]->{'y'} += $diff;
	    $g->{'text'}[1]->{'y'} += $diff;
	}

	$svg_hard[0]{'text'}[0]->{'y'} += $diff;
	$svg_hard[0]{'text'}[1]->{'y'} += $diff;
	$svg_hard[0]{'rect'}->{'y'} += $diff;
    }
    else {
	# move appl down
	my $diff = ($arch_h - $app_h) / 2;
	$svg_app[0]{'text'}[0]->{'y'} += $diff;
	$svg_app[0]{'text'}[1]->{'y'} += $diff;
	$svg_app[0]{'rect'}->{'y'} += $diff;

	my $gI = -1;
	while(my $g = $svg_app[0]{'g'}[++$gI]) {
	    $g->{'rect'}->{'y'} += $diff;
	    $g->{'text'}[0]->{'y'} += $diff;
	    $g->{'text'}[1]->{'y'} += $diff;
	}
    }

    $max_height = ($y_offset > $max_height) ? $y_offset : $max_height;

    if(defined($mapping[0]->{'mapping'})) {
	# loop here
	for(my $_i=0;$_i<@{$mapping[0]->{'mapping'}};$_i++) {
	    my @svg_alloc;
	    push (@svg_alloc, {'line' => []});
	    # allocations
	    my $aI = -1;
	    my $filename;
	    $filename = $svg . '/' . $mapping[0]->{'mapping'}[$_i]->{'id'} . '.svg';

	    while(my $_alloc = $mapping[0]->{'mapping'}[$_i]->{'map'}[++$aI]) {
		$filename = $svg . '/' . $mapping[0]->{'mapping'}[$_i]->{'id'} . '.svg';
		my ($x1, $y1, $x2, $y2, $col);
		# find the start and end elements in the @svg_app || @svg_le1 || @svf_fml
		# $_alloc{'start'} should be in the application
		if($_alloc->{'start'} eq $svg_app[0]{'id'}) {
		    # its the application, find the center of the rect
		    $x1 = $svg_app[0]{'rect'}->{'x'} + $svg_app[0]{'rect'}->{'width'};
		    $y1 = $svg_app[0]{'rect'}->{'y'} + ($svg_app[0]{'rect'}->{'height'} / 2);
		}
		else {
		    my $pI = -1;
		    while(my $_part = $svg_app[0]{'g'}[++$pI]) {
			if($_alloc->{'start'} eq $_part->{'id'}) {
			    # get the rect details
			    $x1 = $_part->{'rect'}->{'x'} + $_part->{'rect'}->{'width'};
			    $y1 = $_part->{'rect'}->{'y'} + ($_part->{'rect'}->{'height'} / 2);
			    last;
			}
		    }
		}

		# $_alloc{'end'} should be either hardware, le1 system or core
		if($_alloc->{'end'} eq $svg_hard[0]{'id'}) {
		    # this is the Hardware block
		    $x2 = $svg_hard[0]{'rect'}->{'x'};
		    $y2 = $svg_hard[0]{'rect'}->{'y'} +  + ($svg_hard[0]{'rect'}->{'height'} / 2);
		    $col = $svg_hard[0]{'rect'}->{'col'};
		}
		elsif($_alloc->{'end'} eq $svg_compresc[0]{'id'}) {
		    # computing resource
		    $x2 = $svg_compresc[0]{'rect'}->{'x'};
		    $y2 = $svg_compresc[0]{'rect'}->{'y'} + ($svg_compresc[0]{'rect'}->{'height'} / 2);
		    $col = $svg_compresc[0]{'rect'}->{'col'};
		}
		else {
		    # should be a core
		    my $cI = -1;
		    while(my $_core = $svg_compresc[0]{'g'}[++$cI]) {
			if($_alloc->{'end'} eq $_core->{'id'}) {
			    # get the rect details
			    $x2 = $_core->{'rect'}->{'x'};
			    $y2 = $_core->{'rect'}->{'y'} + ($_core->{'rect'}->{'height'} / 2);
			    $col = $_core->{'rect'}->{'col'};
			    last;
			}
		    }
		}

		# create a line in @svg_alloc
		push (@{$svg_alloc[0]{'line'}}, {'x1' => $x1,
						 'y1' => $y1,
						 'x2' => $x2,
						 'y2' => $y2,
						 'stroke' => $col,
						 'stroke-width' => 1,
						 'stroke-dasharray' => '9, 5'
		      });
	    }

	    # create a new file
	    open FILE, "> $filename" or die 'Could not create file ' . $filename . ' (' . $! . ')' . "\n";
	    my @svg;
	    push(@svg, {'g' => [@svg_alloc, @svg_app, @svg_compresc, @svg_hard], 'width' => $max_width, 'height' => $max_height, 'viewBox' => '0 0 ' . $max_width . ' ' . $max_height, 'xmlns' => 'http://www.w3.org/2000/svg', 'version' => '1.1'});
	    print FILE (XMLout(@svg, rootname=>'svg'));
	    close FILE;
	}
    }
    else {
	my $filename = $svg . '/orig.svg';
	open FILE, "> $filename" or die 'Could not create file ' . $filename . ' (' . $! . ')' . "\n";
	my @svg;
	push(@svg, {'g' => [@svg_app, @svg_compresc, @svg_hard], 'width' => $max_width, 'height' => $max_height, 'viewBox' => '0 0 ' . $max_width . ' ' . $max_height, 'xmlns' => 'http://www.w3.org/2000/svg', 'version' => '1.1'});
	print FILE (XMLout(@svg, rootname=>'svg'));
	close FILE;
    }

    # then create a webpage to view them
    open FILE, "> $svg/view.html" or die 'Could not create file (' . $! . ')' . "\n";
    print FILE '<!DOCTYPE html>';
    print FILE '<head>' . "\n";
    print FILE '<title>Permutations</title>' . "\n";
    print FILE '</head>' . "\n";
    print FILE '<body style="padding: 0; margin: 0;">' . "\n";
    print FILE '<div id="container" style="width:100%; padding: 0; margin: 0;">' . "\n";
    print FILE '<div style="width:' . $max_width . 'px; margin: 0 auto;">' . "\n";
    my $pwd = readpipe('pwd');
    chomp($pwd);
    if(defined($mapping[0]->{'mapping'})) {
	print FILE '<p>All possible permutations (' . @{$mapping[0]->{'mapping'}} . ') of allocations from file: ' . $pwd . '/' . $in . '</p>' . "\n";
	for(my $_i=0;$_i<@{$mapping[0]->{'mapping'}};$_i++) {
	    print FILE '<div style="width: ' . $max_width . 'px">' . "\n";
	    print FILE '<p>Mapping identifier: ' . $mapping[0]->{'mapping'}[$_i]->{'id'} . '</p>' . "\n";
	    print FILE '<img src="' . $mapping[0]->{'mapping'}[$_i]->{'id'} . '.svg"/>' . "\n";
	    print FILE '</div>' . "\n";
	}
    }
    else {
	print FILE '<p>All possible permutations of allocations from file: ' . $pwd . '/' . $in . '</p>' . "\n";
	print FILE '<div style="width: ' . $max_width . 'px">' . "\n";
	print FILE '<p>Mapping identifier: orig</p>' . "\n";
	print FILE '<img src="orig.svg"/>' . "\n";
	print FILE '</div>' . "\n";
    }
    print FILE '</div>' . "\n";
    print FILE '</div>' . "\n";
    print FILE '</body>' . "\n";
    close FILE;
}

exit 0;
