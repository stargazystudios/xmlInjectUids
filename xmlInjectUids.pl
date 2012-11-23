#!/usr/bin/perl -w

#Copyright (c) 2012, Stargazy Studios
#All Rights Reserved

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#xmlInjectUids will search an input XSD schema for Types with Processing Instruction named 
# with a specified keyword (default 'uid'). Elements of these identified Types are then 
#found in the schema, and their names stored. The input XML file is then parsed to find 
#elements with these names, count them, and give each a uid. The uids are injected it into
# the existing data structure in an attribute named with a given keyword. The data 
#structure is output to the output XML file.

#By default, the scope of uid enumeration is global i.e. two Elements of the same Type, 
#which has been flagged with the "uidGenerator" Processing Instruction, but appearing at 
#different xpath locations, will count towards the same enumeration.

#TODO: A future option may allow custom scoping of Type enumerations.

#TODO: If the uids stored in the XML static data are to be used to index dynamic, run-time
# data, then storing the size of the uid range could be useful when allocating memory, and 
# when iterating across data with for loops. Knowing where to store the total count would 
#need work: find the longest sub-path in an Element's xpath where there was no aggregation
# of Elements, and store the count in the lower-level, uniquely tagged 
#Element. The name of the Attribute to store the count in can either be a variation on the
# Element name, or its Type.

use strict;
use Getopt::Long;
use XML::LibXML;
use Data::Dumper;

sub checkTypeAndExpandElement{
	my ($element,$elementPath,$xmlData,$uidTypesHashRef,$uidElementsHashRef) = @_;
	
	if ($element->hasAttribute("type")){
		my $elementType = $element->getAttribute("type");
		
		#if the element's complexType matches a uid keyword
		if (exists $$uidTypesHashRef{$elementType}){
		
			#check if this element has already been expanded, and if so terminate
			if (exists $$uidElementsHashRef{$elementPath}){
				return;
			}
			
			#otherwise, add the element path to the hash
			else{
				#DEBUG
				#print "Storing $elementPath\n";
				$$uidElementsHashRef{$elementPath} = $elementType;
			}
		}
		
		#process child elements
		foreach my $complexType ($xmlData->findnodes('/xs:schema/xs:complexType[@name="'.$elementType.'"]')){
			foreach my $childElement ($complexType->findnodes("./xs:sequence/xs:element")){
				if ($childElement->hasAttribute("name")){
					my $childElementPath = $elementPath."/".$childElement->getAttribute("name");
					checkTypeAndExpandElement($childElement,$childElementPath,$xmlData,$uidTypesHashRef,$uidElementsHashRef);
				}
			}
		}
	}
}

sub searchElements{
	#Search the passed hash of XSD elements for Complex Type keywords, expanding any that
	#are found to continue the search. As the name of an element can be duplicated within 
	#different types, the hierarchy of the path to the name must be stored along with it.
	#XML element names can not contain spaces, so this character can be used to delineate
	#members of the hierarchy.
	 
	#Loop detection can be made by comparing the hierarchy path element names to the 
	#current one under consideration.
	
	my ($xmlData,$uidTypesHashRef,$uidElementsHashRef) = @_;

	#iterate through all elements
	foreach my $element ($xmlData->findnodes("/xs:schema/xs:element")){
		#check element type against list of Type keywords
		if ($element->hasAttribute("name")){
			#DEBUG
			#print "Processing ".$element->getAttribute("name")."\n";
			checkTypeAndExpandElement($element,"/".$element->getAttribute("name"),$xmlData,$uidTypesHashRef,$uidElementsHashRef);
		}
	}
}

my $xsdIn = '';
my $uidGeneratorPI = 'uidGenerator'; #keyword to denote uid Processing Instruction

my $xmlIn = '';
my $uidKey = 'uid'; #keyword to name uid field that needs generating in a Type
my $xmlOut = 'xmlInjectUids.out.xml';

GetOptions(	'xsdIn=s' => \$xsdIn,
			'uidGeneratorPI=s' => \$uidGeneratorPI,
			'uidKey=s' => \$uidKey,
			'xmlIn=s' => \$xmlIn,
			'xmlOut=s' => \$xmlOut);

my $parserLibXML = XML::LibXML->new();

#parse xsd schema to find keywords, storing array of Type names that contain the uid key
if($xsdIn && $xmlIn ){
	my $xmlData = $parserLibXML->parse_file($xsdIn);
	
	if($xmlData){
		my %uidTypes;
		
		#iterate through all complexTypes in the schema
		foreach my $type ($xmlData->findnodes('/xs:schema/xs:complexType[processing-instruction("'.$uidGeneratorPI.'")]')){
			if($type->hasAttribute("name")){
				$uidTypes{$type->getAttribute("name")} = 0;
			}
		}
	
		#DEBUG		
		#print Dumper(%uidTypes);
		
		#on a second pass, identify which element names are of a Type requiring a uid
		#-process xs:complexType:
		#-process xs:element:
		my %uidElements;
		my $uidElementsHashRef = \%uidElements;
		
		#recursively search for elements with keyword types and store hierarchy paths
		searchElements($xmlData,\%uidTypes,$uidElementsHashRef);

		#DEBUG check uidElements for correctness
		#print Dumper($uidElementsHashRef);
		
		#parse xml in file to find Types, counting them and injecting uid keys
		$xmlData = $parserLibXML->parse_file($xmlIn);
		
		if($xmlData){			
			#inject uids in XMLData
			foreach my $elementPath (keys %{$uidElementsHashRef}){
				foreach my $uidElement ($xmlData->findnodes($elementPath)){
					#add/edit the uidKey attribute of each element
					my $uidElementType = $uidElements{$elementPath};
					$uidElement->setAttribute($uidKey,$uidTypes{$uidElementType});
					$uidTypes{$uidElementType}++;
				}
			}
			
			#DEBUG check uidElements for correctness
			#print Dumper($uidElementsHashRef);
			
			#output XMLData to file
			$xmlData->toFile($xmlOut);
		}
		else{print STDERR "xmlIn($xmlIn) is not a valid xml file. EXIT\n";}
	}
	else{print STDERR "xsdIn($xsdIn) is not a valid xml file. EXIT\n";}
}
else{print STDERR "Options --xsdIn --xmlIn are required. EXIT\n";}