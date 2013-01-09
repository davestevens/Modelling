#!/usr/bin/perl

# Expand application

use strict;
use XML::Simple;
use Data::Dumper;

our ($Hardware, $ComputingResource, $Processor, $Alloc);
our ($hr_attribute_name, $hcr_attribute_name, $hp_attribute_name, $a_attribute_name);

require "global.pl";

setup_marte(2.2);

our ($in, $out, $top);
parse_args(@ARGV);

if(($in eq '') || ($out eq '')) {
    print 'You have not specified all required files.' . "\n";
    exit -1;
}

# Check $in for architectural elements
my $XMI = XMLin($in, KeyAttr=>['list'], ForceArray=>1);
my $Model = $XMI->{'uml:Model'}[0];

my %Objects;
# Create a hash of all xmi:ids
get_objects(\%Objects, $XMI, 'TOP');

my $num_cores = 0;
my %_cores;
my $architectureI = -1;
while(my $HwComputingResource = $XMI->{$ComputingResource}[++$architectureI]) {
    # need to look for cores
    # find this ComputingResource class and get the property values
    my $packagedElement = $Objects{$HwComputingResource->{$hcr_attribute_name}}->{'ref'};
    my $ownedAttributeI = -1;
    while(my $ownedAttribute = $packagedElement->{'ownedAttribute'}[++$ownedAttributeI]) {
	# Find this core as a HwProc
	my $coresI = -1;
	while(my $HwProcessor = $XMI->{$Processor}[++$coresI]) {
	    if($HwProcessor->{$hp_attribute_name} eq $ownedAttribute->{'xmi:id'}) {
		++$num_cores;
		$_cores{$ownedAttribute->{'xmi:id'}} = 1;
	    }
	}
    }
}

# Find top level, see if there are any attributes with wildcard multiplicities
my $wildcard;

my $ownedAttributeI = -1;
while(my $ownedAttribute = $top->{'ref'}->{'ownedAttribute'}[++$ownedAttributeI]) {
    if($ownedAttribute->{'xmi:type'} eq 'uml:Property') {
	if(defined($ownedAttribute->{'upperValue'})) {
	    if($ownedAttribute->{'upperValue'}[0]->{'value'} eq "*") {
		# This is the part to expand
		#print 'Need to expand ' . $ownedAttribute->{'name'} . "\n";
		$wildcard = $ownedAttribute;
	    }
	}
    }
}

if(!$wildcard) {
    # Nothing to be expanded
    print 'Nothing found with wildcard multiplicity.' . "\n";
    exit 1;
}

# Work out allocated cores
my $allocationI = -1;
while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
    my $dep = $Objects{$allocation->{$a_attribute_name}}->{'ref'};
    delete($_cores{$dep->{'supplier'}});
}

# Create $num_cores - (allocated cores) instances
#my $num_replicate = $num_cores - ((keys %_cores) - 2);
my $num_replicate = (keys %_cores);
print $num_replicate . "\n";
undef(%_cores);

# Find Interface Realisation from Class
my $interface_for_fork = $Objects{$Objects{$wildcard->{'type'}}->{'ref'}->{'interfaceRealization'}[0]->{'supplier'}}->{'ref'};

if(!$interface_for_fork) {
    print 'Could not find interface (interface_for_fork).' . "\n";
    exit 1;
}

# Create 2 Classes Fork & Join and $num_replicate instances of $Class{$wildcard->{'type'}}

# Fork Class
# Copy $interface_for_fork ownedReception
# Create an ownedOperation for each ownedReception
# Add ownedComment (body) to each ownedOperation
# Add attribute for each ownedOperation to perform round robin
# interfaceRealization to $interface_for_fork
# 1 input port (linked to interface)
# $num_replicate output ports
# Create state machine
## initial state -> state1 (init)
## initial state -> inital state (trigger: signal of reception, action: call ownedOperation)

my $fork_class = {'xmi:type' => 'uml:Class',
		  'xmi:id' => 'autogen_fork_class',
		  'name' => 'autogen_fork_class',
		  'interfaceRealization' => {'client' => 'autogen_fork_class',
					     'supplier' => $Objects{$wildcard->{'type'}}->{'ref'}->{'interfaceRealization'}[0]->{'supplier'},
					     'contract' => $Objects{$wildcard->{'type'}}->{'ref'}->{'interfaceRealization'}[0]->{'contract'},
					     'xmi:id' => 'autogen_fork_class_interface_realisation'},
		  'ownedReception' => $interface_for_fork->{'ownedReception'},
		  'ownedOperation' => [],
		  # need to make a copy of this rather than copying the reference
		  'ownedAttribute' => [{'xmi:type' => 'uml:Property',
					'name' => 'num',
					'xmi:id' => 'autogen_fork_class_num',
					'isUnique' => 'false',
					'type' => {'xmi:type' => 'uml:Primitive',
						   'href' => 'http://schema.omg.org/spec/UML/2.1.1/uml.xml#Integer'}}
		      ]
};

# Create a state machine and initialisation operation
my $autogen_fork_init_body = 'self->num = ' . $num_replicate . ';' . "\n";
my $autogen_fork_statemachine = {'name' => 'State Machine',
				 'xmi:id' => 'autogen_fork_class_statemachine',
				 'xmi:type' => 'uml:StateMachine',
				 'region' => {'name' => 'Region',
					      'subvertex' => [{'name' => 'Initial State',
							       'xmi:id' => 'autogen_fork_class_initialstate',
							       'xmi:type' => 'uml:Pseudostate'},
							      {'name' => 'Ready',
							       'xmi:id' => 'autogen_fork_class_ready',
							       'xmi:type' => 'uml:State'}],
					      'transition' => [{'name' => 'init',
								'source' => 'autogen_fork_class_initialstate',
								'target' => 'autogen_fork_class_ready',
								'xmi:type' => 'uml:Transition',
								'effect' => {'xmi:type' => 'uml:OpaqueBehavior',
									     'body' => ['autogen_fork_class__init(self);']}}]}
};

my $receptionI = -1;
while(my $reception = $fork_class->{'ownedReception'}[++$receptionI]) {
    # Create a round robin attribute
#    my $attr = {'xmi:type' => 'uml:Property',
#		'xmi:id' => $reception->{'name'} . '_roundrobin',
#		'name' => $reception->{'name'} . '_roundrobin',
#		'isUnique' => 'false',
#		'type' => {'xmi:type' => 'uml:Primitive',
#			   'href' => 'http://schema.omg.org/spec/UML/2.1.1/uml.xml#Integer'}};
#    push(@{$fork_class->{'ownedAttribute'}}, $attr);
#
#    $autogen_fork_init_body .= 'self->' . $reception->{'name'} . '_roundrobin = 0;' . "\n";

    # Create a new operation named same as reception
    my $operation = {'name' => $reception->{'name'} . '_op',
		     'xmi:id' => $reception->{'name'} . '_op',
		     'xmi:type' => 'uml:Operation',
		     'ownedParameter' => $reception->{'ownedParameter'}};
    push(@{$fork_class->{'ownedOperation'}}, $operation);

    my $body = '';
    my @args;
    my $transition_args = '';
    for(my $i=0;$i<@{$reception->{'ownedParameter'}};++$i) {
	if($transition_args ne '') { $transition_args .= ', '; }
	push(@args, $reception->{'ownedParameter'}[$i]->{'name'});
	$transition_args .= 'params->' . $reception->{'ownedParameter'}[$i]->{'name'};
    }


    my $event = '';
    # Find signalEvent
    foreach my $key (keys %Objects) {
	if($Objects{$key}->{'element'} eq 'packagedElement') {
	    if(($Objects{$key}->{'ref'}->{'xmi:type'} eq 'uml:SignalEvent')
	       &&
	       ($Objects{$key}->{'ref'}->{'signal'} eq $reception->{'signal'})) {
		$event = $key;
		last;
	    }
	}
    }


    push(@{$autogen_fork_statemachine->{'region'}->{'transition'}}, {'name' => $reception->{'name'},
								     'source' => 'autogen_fork_class_ready',
								     'target' => 'autogen_fork_class_ready',
								     'xmi:type' => 'uml:Transition',
								     'effect' => {'xmi:type' => 'uml:OpaqueBehavior',
										  'body' => ['autogen_fork_class__' . $reception->{'name'} . '_op(self, ' . $transition_args . ');']},
								     'trigger' => {'name' => $reception->{'name'} . '_trigger',
										   'event' => $event,
										   'xmi:type' => 'uml:Trigger'}
	 });

    # Create $num_replicate function calls
    for(my $i=0;$i<$num_replicate;++$i) {
	#$body .= $interface_for_fork->{'name'} . '__' . $reception->{'name'} . '(self->out_' . $i . ', ' . $args[0] . '+(((' . $args[1] . '/self->num)*4)*' . $i . '), (' . $args[1] . '/self->num)';
	$body .= $interface_for_fork->{'name'} . '__' . $reception->{'name'} . '(self->out_' . $i . ', ' . $args[0] . '+(((' . $args[1] . '*' . $args[2] . ')/self->num)*' . $i . '), ' . $args[1] . ', (' . $args[2] . '/self->num)';
	for(my $j=3;$j<@args;++$j) {
	    $body .= ', ' . $args[$j];
	}
	$body .= ');' . "\n";
    }

    # Create body
    $operation->{'ownedComment'} = [{'body' => [$body],
				     'xmi:type' => 'uml:Comment',
				     'xmi:id' => ''
				    }];
}

push(@{$fork_class->{'ownedOperation'}}, {'name' => 'init',
					  'xmi:id' => 'autogen_fork_class_init',
					  'xmi:type' => 'uml:Operation',
					  'ownedComment' => [{'body' => [$autogen_fork_init_body],
							      'xmi:type' => 'uml:Comment',
							      'xmi:id' => ''}]});
push(@{$fork_class->{'ownedBehavior'}}, $autogen_fork_statemachine);


# Create input port
push(@{$fork_class->{'ownedAttribute'}}, {'xmi:type' => 'uml:Port',
					  'xmi:id' => 'autogen_fork_class_in',
					  'name' => 'in',
					  'type' => $interface_for_fork->{'xmi:id'},
					  'aggregation' => 'composite'});

# Create output ports
# Find the required interface which uses $interface_for_fork
my $packagedElementI = -1;
my $interface_for_fork_req;
while(my $packagedElement = $Model->{'packagedElement'}[++$packagedElementI]) {
    if(($packagedElement->{'xmi:type'} eq 'uml:Usage')
       &&
       ($packagedElement->{'supplier'} eq $interface_for_fork->{'xmi:id'})){
	$interface_for_fork_req = $packagedElement;
    }
}

if(!$interface_for_fork_req) {
    print 'Could not find interface (interface_for_fork_req).' . "\n";
    exit 1;
}

for(my $i=0;$i<$num_replicate;++$i) {
    push(@{$fork_class->{'ownedAttribute'}}, {'xmi:type' => 'uml:Port',
					      'xmi:id' => 'autogen_fork_class_out_' . $i,
					      'name' => 'out_' . $i,
					      'type' => $interface_for_fork_req->{'client'},
					      'aggregation' => 'composite'});
}

push(@{$Model->{'packagedElement'}}, $fork_class);


# Join Class
# copy operations from interface linked through interface_req
# add body to all operations
# interface realization to interface_req
# 1 output port
# $num_replicate input ports

my $interface_for_join;
my $interface_for_join_req;
my $ownedAttributeI = -1;
while(my $ownedAttribute = $Objects{$wildcard->{'type'}}->{'ref'}->{'ownedAttribute'}[++$ownedAttributeI]) {
    if($ownedAttribute->{'xmi:type'} eq 'uml:Port') {
	if($ownedAttribute->{'type'} ne $interface_for_fork->{'xmi:id'}) {
	    # type points to the required interface
	    #print $ownedAttribute->{'xmi:id'} . "\n";
	    # Find that interface
	    $interface_for_join_req = $Objects{$ownedAttribute->{'type'}}->{'ref'};

	    # Then find the usage which links to this interface
	    my $pE = $Objects{$interface_for_join_req->{'clientDependency'}}->{'ref'};

	    $interface_for_join = $Objects{$pE->{'supplier'}}->{'ref'};
	}
	if($interface_for_join) {
	    last;
	}
    }
    if($interface_for_join) {
	last;
    }
}

my $join_class = {'xmi:type' => 'uml:Class',
		  'xmi:id' => 'autogen_join_class',
		  'name' => 'autogen_join_class',
		  'interfaceRealization' => {'client' => 'autogen_join_class',
					     'supplier' => $interface_for_join->{'xmi:id'},
					     'contract' => $interface_for_join->{'xmi:id'},
					     'xmi:id' => 'autogen_join_class_interface_realisation'},
		  'ownedAttribute' => [{'xmi:type' => 'uml:Property',
					'name' => 'num',
					'xmi:id' => 'autogen_fork_class_num',
					'isUnique' => 'false',
					'type' => {'xmi:type' => 'uml:Primitive',
						   'href' => 'http://schema.omg.org/spec/UML/2.1.1/uml.xml#Integer'}}
		      ],
		  'ownedOperation' => []
};

my $autogen_join_init_body = 'self->num = ' . $num_replicate . ';' . "\n";
my $autogen_join_statemachine = {'name' => 'State Machine',
				 'xmi:id' => 'autogen_join_class_statemachine',
				 'xmi:type' => 'uml:StateMachine',
				 'region' => {'name' => 'Region',
					      'subvertex' => [{'name' => 'Initial State',
							       'xmi:id' => 'autogen_join_class_initialstate',
							       'xmi:type' => 'uml:Pseudostate'},
							      {'name' => 'Ready',
							       'xmi:id' => 'autogen_join_class_ready',
							       'xmi:type' => 'uml:State'}],
					      'transition' => [{'name' => 'init',
								'source' => 'autogen_join_class_initialstate',
								'target' => 'autogen_join_class_ready',
								'xmi:type' => 'uml:Transition',
								'effect' => {'xmi:type' => 'uml:OpaqueBehavior',
									     'body' => ['autogen_join_class__init(self);']}}]}
};


# Create operation bodies
my $operationI = -1;
while(my $operation = $interface_for_join->{'ownedOperation'}[++$operationI]) {
    my @args;
    for(my $i=0;$i<@{$operation->{'ownedParameter'}};++$i) {
	push(@args, $operation->{'ownedParameter'}[$i]->{'name'});
    }

    # Create done attributes
    push(@{$join_class->{'ownedAttribute'}}, {'xmi:type' => 'uml:Property',
					      'name' => $operation->{'name'} . '_done',
					      'xmi:id' => 'autogen_fork_class_' . $operation->{'name'} . '_done',
					      'isUnique' => 'false',
					      'type' => {'xmi:type' => 'uml:Primitive',
							 'href' => 'http://schema.omg.org/spec/UML/2.1.1/uml.xml#Integer'}});

    $autogen_join_init_body .= 'self->' . $operation->{'name'} . '_done = 0;' . "\n";

    my $body = '++self->' . $operation->{'name'} . '_done;' . "\n";
    $body .= 'if(self->' . $operation->{'name'} . '_done == self->num) {' . "\n";
    $body .= "\t" . $interface_for_join->{'name'} . '__' . $operation->{'name'} . '(self->out, ' . $args[0] . ', (' . $args[1] . ' * self->num)';
    for(my $j=2;$j<@args;++$j) {
	$body .= ', ' .$args[$j];
    }
    $body .= ');' . "\n";
    $body .= "\t" . 'self->' . $operation->{'name'} . '_done = 0;' . "\n";
    $body .= '}';

    # Create body
    push(@{$join_class->{'ownedOperation'}}, {'name' => $operation->{'name'},
					      'isAbstract' => $operation->{'isAbstract'},
					      'xmi:id' => $operation->{'xmi:id'},
					      'xmi:type' => 'uml:Operation',
					      'ownedParameter' => $operation->{'ownedParameter'},
					      'ownedComment' => [{'body' => [$body],
								  'xmi:type' => 'uml:Comment',
								  'xmi:id' => ''
								 }]
	 });
}

push(@{$join_class->{'ownedOperation'}}, {'name' => 'init',
					  'xmi:id' => 'autogen_join_class_init',
					  'xmi:type' => 'uml:Operation',
					  'ownedComment' => [{'body' => [$autogen_join_init_body],
							      'xmi:type' => 'uml:Comment',
							      'xmi:id' => ''}]});
push(@{$join_class->{'ownedBehavior'}}, $autogen_join_statemachine);


# Create output port
push(@{$join_class->{'ownedAttribute'}}, {'xmi:type' => 'uml:Port',
					  'xmi:id' => 'autogen_join_class_out',
					  'name' => 'out',
					  'type' => $interface_for_join_req->{'xmi:id'},
					  'aggregation' => 'composite'});

# Create input ports
for(my $i=0;$i<$num_replicate;++$i) {
    push(@{$join_class->{'ownedAttribute'}}, {'xmi:type' => 'uml:Port',
					      'xmi:id' => 'autogen_join_class_in_' . $i,
					      'name' => 'in_' . $i,
					      'type' => $interface_for_join->{'xmi:id'},
					      'aggregation' => 'composite'});
}

push(@{$Model->{'packagedElement'}}, $join_class);

# Create $num_replicate objects in top
for(my $i=0;$i<$num_replicate;++$i) {
    push(@{$top->{'ref'}->{'ownedAttribute'}}, {'xmi:type' => 'uml:Property',
						'xmi:id' => 'autogen_' . $Objects{$wildcard->{'type'}}->{'ref'}->{'name'} . '_' . $i,
						'name' => $Objects{$wildcard->{'type'}}->{'ref'}->{'name'} . '_' . $i,
						'type' => $wildcard->{'type'},
						'aggregation' => 'composite'});
# Create alloc and uml:dependency for this objects
    push(@{$XMI->{$Alloc}}, {'xmi:id' => 'autogenerated_allocation_' . $i,
			     $a_attribute_name => 'autogenerated_dependency_' . $i});
    push(@{$Model->{'packagedElement'}}, {'xmi:type' => 'uml:Dependency',
					  'xmi:id' => 'autogenerated_dependency_' . $i,
					  'supplier' => 'autogen_Processor_i' . $i,
					  'client' => 'autogen_' . $Objects{$wildcard->{'type'}}->{'ref'}->{'name'} . '_' . $i});
}

# Create 1 fork class in top
push(@{$top->{'ref'}->{'ownedAttribute'}}, {'xmi:type' => 'uml:Property',
					    'xmi:id' => 'autogen_fork_object',
					    'name' => 'fork',
					    'type' => 'autogen_fork_class',
					    'aggregation' => 'composite'});

# Create 1 join class in top
push(@{$top->{'ref'}->{'ownedAttribute'}}, {'xmi:type' => 'uml:Property',
					    'xmi:id' => 'autogen_join_object',
					    'name' => 'join',
					    'type' => 'autogen_join_class',
					    'aggregation' => 'composite'});

# Move connections from object to fork and join
# Check if connected object, if allocated create new allocation for fork and join
my $ownedConnectorI = -1;
my $fork_port;
my $join_port;
while(my $ownedConnector = $top->{'ref'}->{'ownedConnector'}[++$ownedConnectorI]) {
    my $endI = -1;
    while(my $end = $ownedConnector->{'end'}[++$endI]) {
	if($end->{'partWithPort'} eq $wildcard->{'xmi:id'}) {
	    # This is a connector of interest
	    # Find if it is an input or output
	    my $ownedAttribute = $Objects{$end->{'role'}}->{'ref'};
	    if($ownedAttribute->{'type'} eq $interface_for_fork->{'xmi:id'}) {
		# Fork
		$fork_port = $ownedConnector->{'end'}[$endI]->{'role'};
		$end->{'partWithPort'} = 'autogen_fork_object';
		$end->{'role'} = 'autogen_fork_class_in';

		# If the other end has a dependency which is linked to a MARTE allocate, copy it
		my $part_id = $ownedConnector->{'end'}[(($endI == 0) ? 1 : 0)]->{'partWithPort'};
		# Check dependencies
		my $packagedElementI = -1;
		while(my $packagedElement = $Model->{'packagedElement'}[++$packagedElementI]) {
		    if(($packagedElement->{'xmi:type'} eq 'uml:Dependency')
		       &&
		       ($packagedElement->{'client'} eq $part_id)) {
			# Check MARTE allocates
			my $allocationI = -1;
			while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
			    if($allocation->{'base_Dependency'} eq $packagedElement->{'xmi:id'}) {
				# Copy it
				push(@{$XMI->{$Alloc}}, {'xmi:id' => $allocation->{'xmi:id'} . '_copy',
							 $a_attribute_name => $allocation->{'base_Dependency'} . '_copy'});
				push(@{$Model->{'packagedElement'}}, {'name' => '',
								      'client' => 'autogen_fork_object',
								      'supplier' => $packagedElement->{'supplier'},
								      'xmi:id' => $allocation->{'base_Dependency'} . '_copy',
								      'xmi:type' => 'uml:Dependency'});
				last;
			    }
			}
		    }
		}
		last;
	    }
	    if($ownedAttribute->{'type'} eq $interface_for_join_req->{'xmi:id'}) {
		# Join
		$join_port = $ownedConnector->{'end'}[$endI]->{'role'};
		$end->{'partWithPort'} = 'autogen_join_object';
		$end->{'role'} = 'autogen_join_class_out';

		# If the other end has a dependency which is linked to a MARTE allocate, copy it
		my $part_id = $ownedConnector->{'end'}[(($endI == 0) ? 1 : 0)]->{'partWithPort'};
		# Check dependencies
		my $packagedElementI = -1;
		while(my $packagedElement = $Model->{'packagedElement'}[++$packagedElementI]) {
		    if(($packagedElement->{'xmi:type'} eq 'uml:Dependency')
		       &&
		       ($packagedElement->{'client'} eq $part_id)) {
			# Check MARTE allocates
			my $allocationI = -1;
			while(my $allocation = $XMI->{$Alloc}[++$allocationI]) {
			    if($allocation->{'base_Dependency'} eq $packagedElement->{'xmi:id'}) {
				# Copy it
				push(@{$XMI->{$Alloc}}, {'xmi:id' => $allocation->{'xmi:id'} . '_copy',
							 $a_attribute_name => $allocation->{'base_Dependency'} . '_copy'});
				push(@{$Model->{'packagedElement'}}, {'name' => '',
								      'client' => 'autogen_join_object',
								      'supplier' => $packagedElement->{'supplier'},
								      'xmi:id' => $allocation->{'base_Dependency'} . '_copy',
								      'xmi:type' => 'uml:Dependency'});
				last;
			    }
			}
		    }
		}
		last;
	    }
	}
    }
}

# Remove wildcard object from top
my $ownedAttributeI = -1;
while(my $ownedAttribute = $top->{'ref'}->{'ownedAttribute'}[++$ownedAttributeI]) {
    if($ownedAttribute->{'xmi:type'} eq 'uml:Property') {
	if(defined($ownedAttribute->{'upperValue'})) {
	    if($ownedAttribute->{'upperValue'}[0]->{'value'} eq "*") {
		splice(@{$top->{'ref'}->{'ownedAttribute'}}, $ownedAttributeI, 1);
		last;
	    }
	}
    }
}

# Create new connections between fork/join and replicated objects
for(my $i=0;$i<$num_replicate;++$i) {
    push(@{$top->{'ref'}->{'ownedConnector'}}, {'kind' => 'delegation',
						'xmi:id' => 'fork_' . $i,
						'end' => [
						    {'isUnique' => 'false',
						     'partWithPort' => 'autogen_fork_object',
						     'role' => 'autogen_fork_class_out_' . $i},
						    {'isUnique' => 'false',
						     'partWithPort' => 'autogen_' . $Objects{$wildcard->{'type'}}->{'ref'}->{'name'} . '_' . $i,
						     'role' => $fork_port}
						    ]});

    push(@{$top->{'ref'}->{'ownedConnector'}}, {'kind' => 'delegation',
						'xmi:id' => 'join_' . $i,
						'end' => [
						    {'isUnique' => 'false',
						     'partWithPort' => 'autogen_' . $Objects{$wildcard->{'type'}}->{'ref'}->{'name'} . '_' . $i,
						     'role' => $join_port},
						    {'isUnique' => 'false',
						     'partWithPort' => 'autogen_join_object',
						     'role' => 'autogen_join_class_in_' . $i}
						    ]});
}

# Force each Class to have a statemachine (even if it doe nothing)
{
    my $statemachine = {'xmi:type' => 'uml:StateMachine',
			'region' => {'subvertex' => [{'xmi:id' => 'a',
						      'xmi:type' => 'uml:Pseudostate'},
						     {'xmi:id' => 'b',
						      'xmi:type' => 'uml:State'}],
				     'transition' => {'source' => 'a',
						      'target' => 'b',
						      'xmi:type' => 'uml:Transition'}
			}};

    my $packagedElementI = -1;
    while(my $packagedElement = $Model->{'packagedElement'}[++$packagedElementI]) {
	if(!defined($packagedElement->{'ownedBehavior'})
	   &&
	   ($packagedElement->{'xmi:type'} eq 'uml:Class')) {
	    $packagedElement->{'ownedBehavior'} = $statemachine;
	}
    }
}

open FILE, "> $out" or die 'Could not open file: ' . $out . ' (' . $! . ')' . "\n";
print FILE XMLout($XMI, rootname => 'xmi:XMI', XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>');
close FILE;

exit 0;
